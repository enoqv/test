package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/enoqv/test/internal/cache"
	"github.com/enoqv/test/internal/model"
	"github.com/enoqv/test/internal/repository"
	"github.com/enoqv/test/internal/service"
)

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

func newTestHandler() (*MemberHandler, *service.MemberService) {
	svc := service.NewMemberService(newFakeRepo(), cache.NewMemoryCache(), "test-secret", time.Hour, time.Minute)
	return NewMemberHandler(svc), svc
}

func doJSON(t *testing.T, h http.Handler, method, path string, body any, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatalf("encode body: %v", err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHealth(t *testing.T) {
	h, _ := newTestHandler()
	rec := doJSON(t, h.Routes(), http.MethodGet, "/healthz", nil, nil)
	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rec.Code)
	}
}

func TestRegisterAndLogin(t *testing.T) {
	h, _ := newTestHandler()
	router := h.Routes()

	// register
	rec := doJSON(t, router, http.MethodPost, "/api/register", model.RegisterRequest{
		Username: "alice",
		Email:    "alice@example.com",
		Password: "secret123",
	}, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("register status = %d, body = %s", rec.Code, rec.Body.String())
	}

	// login
	rec = doJSON(t, router, http.MethodPost, "/api/login", model.LoginRequest{
		Username: "alice",
		Password: "secret123",
	}, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("login status = %d, body = %s", rec.Code, rec.Body.String())
	}

	var resp model.LoginResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Token == "" {
		t.Error("expected token")
	}

	// call /api/me with token
	rec = doJSON(t, router, http.MethodGet, "/api/me", nil, map[string]string{
		"Authorization": "Bearer " + resp.Token,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("me status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var me model.Member
	if err := json.Unmarshal(rec.Body.Bytes(), &me); err != nil {
		t.Fatalf("decode me: %v", err)
	}
	if me.Username != "alice" {
		t.Errorf("got %s, want alice", me.Username)
	}
}

func TestRegister_BadJSON(t *testing.T) {
	h, _ := newTestHandler()
	req := httptest.NewRequest(http.MethodPost, "/api/register", bytes.NewBufferString("not json"))
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", rec.Code)
	}
}

func TestLogin_InvalidCredentials(t *testing.T) {
	h, _ := newTestHandler()
	rec := doJSON(t, h.Routes(), http.MethodPost, "/api/login", model.LoginRequest{
		Username: "nobody",
		Password: "nope",
	}, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}

func TestMe_NoToken(t *testing.T) {
	h, _ := newTestHandler()
	rec := doJSON(t, h.Routes(), http.MethodGet, "/api/me", nil, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}

func TestMe_BadToken(t *testing.T) {
	h, _ := newTestHandler()
	rec := doJSON(t, h.Routes(), http.MethodGet, "/api/me", nil, map[string]string{
		"Authorization": "Bearer not-a-real-token",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", rec.Code)
	}
}
