package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/enoqv/test/internal/cache"
	"github.com/enoqv/test/internal/model"
	"github.com/enoqv/test/internal/repository"
)

// fakeRepo is an in-memory implementation of repository.MemberRepository.
type fakeRepo struct {
	members map[int64]*model.Member
	byName  map[string]int64
	nextID  int64
}

func newFakeRepo() *fakeRepo {
	return &fakeRepo{
		members: make(map[int64]*model.Member),
		byName:  make(map[string]int64),
	}
}

func (f *fakeRepo) Create(_ context.Context, m *model.Member) error {
	f.nextID++
	m.ID = f.nextID
	m.CreatedAt = time.Now()
	m.UpdatedAt = m.CreatedAt
	f.members[m.ID] = m
	f.byName[m.Username] = m.ID
	return nil
}

func (f *fakeRepo) GetByID(_ context.Context, id int64) (*model.Member, error) {
	if m, ok := f.members[id]; ok {
		return m, nil
	}
	return nil, repository.ErrNotFound
}

func (f *fakeRepo) GetByUsername(_ context.Context, username string) (*model.Member, error) {
	if id, ok := f.byName[username]; ok {
		return f.members[id], nil
	}
	return nil, repository.ErrNotFound
}

func newTestService() *MemberService {
	return NewMemberService(newFakeRepo(), cache.NewMemoryCache(), "test-secret", time.Hour, time.Minute)
}

func TestRegister_Success(t *testing.T) {
	svc := newTestService()
	m, err := svc.Register(context.Background(), model.RegisterRequest{
		Username: "alice",
		Email:    "alice@example.com",
		Password: "secret123",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.ID == 0 {
		t.Error("expected ID to be set")
	}
	if m.PasswordHash == "secret123" {
		t.Error("password should be hashed")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(m.PasswordHash), []byte("secret123")); err != nil {
		t.Errorf("hashed password did not match: %v", err)
	}
}

func TestRegister_ValidationErrors(t *testing.T) {
	svc := newTestService()
	tests := []struct {
		name string
		req  model.RegisterRequest
	}{
		{"short username", model.RegisterRequest{Username: "al", Email: "a@b.com", Password: "secret123"}},
		{"bad email", model.RegisterRequest{Username: "alice", Email: "notanemail", Password: "secret123"}},
		{"short password", model.RegisterRequest{Username: "alice", Email: "a@b.com", Password: "x"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.Register(context.Background(), tc.req)
			if !errors.Is(err, ErrValidation) {
				t.Errorf("expected ErrValidation, got %v", err)
			}
		})
	}
}

func TestLogin_Success(t *testing.T) {
	svc := newTestService()
	_, err := svc.Register(context.Background(), model.RegisterRequest{
		Username: "bob",
		Email:    "bob@example.com",
		Password: "hunter2pass",
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	resp, err := svc.Login(context.Background(), model.LoginRequest{
		Username: "bob",
		Password: "hunter2pass",
	})
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if resp.Token == "" {
		t.Error("expected token")
	}
	if resp.Member.Username != "bob" {
		t.Errorf("unexpected username: %s", resp.Member.Username)
	}

	uid, err := svc.VerifyToken(resp.Token)
	if err != nil {
		t.Fatalf("verify token: %v", err)
	}
	if uid != resp.Member.ID {
		t.Errorf("token sub = %d, want %d", uid, resp.Member.ID)
	}
}

func TestLogin_WrongPassword(t *testing.T) {
	svc := newTestService()
	_, _ = svc.Register(context.Background(), model.RegisterRequest{
		Username: "carol",
		Email:    "c@x.com",
		Password: "correctpass",
	})

	_, err := svc.Login(context.Background(), model.LoginRequest{
		Username: "carol",
		Password: "wrongpass",
	})
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("expected ErrInvalidCredentials, got %v", err)
	}
}

func TestLogin_UnknownUser(t *testing.T) {
	svc := newTestService()
	_, err := svc.Login(context.Background(), model.LoginRequest{
		Username: "ghost",
		Password: "whatever",
	})
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("expected ErrInvalidCredentials, got %v", err)
	}
}

func TestGetByID_UsesCache(t *testing.T) {
	repo := newFakeRepo()
	cch := cache.NewMemoryCache()
	svc := NewMemberService(repo, cch, "secret", time.Hour, time.Minute)

	m := &model.Member{Username: "dave", Email: "d@x.com", PasswordHash: "x"}
	_ = repo.Create(context.Background(), m)

	// first call populates cache
	got, err := svc.GetByID(context.Background(), m.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.Username != "dave" {
		t.Errorf("got %s, want dave", got.Username)
	}

	// mutate repository; cached value should still be returned
	repo.members[m.ID].Username = "changed"
	cached, err := svc.GetByID(context.Background(), m.ID)
	if err != nil {
		t.Fatalf("GetByID cached: %v", err)
	}
	if cached.Username != "dave" {
		t.Errorf("expected cached value 'dave', got %s", cached.Username)
	}
}

func TestVerifyToken_Invalid(t *testing.T) {
	svc := newTestService()
	if _, err := svc.VerifyToken("not-a-token"); err == nil {
		t.Error("expected error for invalid token")
	}
}
