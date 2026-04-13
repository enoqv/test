package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/enoqv/test/internal/cache"
	"github.com/enoqv/test/internal/model"
	"github.com/enoqv/test/internal/repository"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrValidation         = errors.New("validation error")
)

type MemberService struct {
	repo          repository.MemberRepository
	cache         cache.Cache
	jwtSecret     []byte
	jwtExpiration time.Duration
	cacheTTL      time.Duration
}

func NewMemberService(repo repository.MemberRepository, c cache.Cache, jwtSecret string, jwtExp, cacheTTL time.Duration) *MemberService {
	return &MemberService{
		repo:          repo,
		cache:         c,
		jwtSecret:     []byte(jwtSecret),
		jwtExpiration: jwtExp,
		cacheTTL:      cacheTTL,
	}
}

func (s *MemberService) Register(ctx context.Context, req model.RegisterRequest) (*model.Member, error) {
	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(req.Email)

	if len(req.Username) < 3 {
		return nil, fmt.Errorf("%w: username must be at least 3 characters", ErrValidation)
	}
	if !strings.Contains(req.Email, "@") {
		return nil, fmt.Errorf("%w: invalid email", ErrValidation)
	}
	if len(req.Password) < 6 {
		return nil, fmt.Errorf("%w: password must be at least 6 characters", ErrValidation)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	m := &model.Member{
		Username:     req.Username,
		Email:        req.Email,
		PasswordHash: string(hash),
	}
	if err := s.repo.Create(ctx, m); err != nil {
		return nil, fmt.Errorf("create member: %w", err)
	}
	return m, nil
}

func (s *MemberService) Login(ctx context.Context, req model.LoginRequest) (*model.LoginResponse, error) {
	m, err := s.repo.GetByUsername(ctx, strings.TrimSpace(req.Username))
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}
	if err := bcrypt.CompareHashAndPassword([]byte(m.PasswordHash), []byte(req.Password)); err != nil {
		return nil, ErrInvalidCredentials
	}

	token, err := s.issueToken(m)
	if err != nil {
		return nil, err
	}
	return &model.LoginResponse{Token: token, Member: m}, nil
}

func (s *MemberService) GetByID(ctx context.Context, id int64) (*model.Member, error) {
	key := memberCacheKey(id)
	var cached model.Member
	if err := s.cache.Get(ctx, key, &cached); err == nil {
		return &cached, nil
	}
	m, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	_ = s.cache.Set(ctx, key, m, s.cacheTTL)
	return m, nil
}

func (s *MemberService) VerifyToken(tokenStr string) (int64, error) {
	tok, err := jwt.Parse(tokenStr, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil || !tok.Valid {
		return 0, fmt.Errorf("invalid token: %w", err)
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return 0, errors.New("invalid claims")
	}
	sub, ok := claims["sub"].(float64)
	if !ok {
		return 0, errors.New("invalid subject claim")
	}
	return int64(sub), nil
}

func (s *MemberService) issueToken(m *model.Member) (string, error) {
	claims := jwt.MapClaims{
		"sub": m.ID,
		"usr": m.Username,
		"exp": time.Now().Add(s.jwtExpiration).Unix(),
		"iat": time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.jwtSecret)
}

func memberCacheKey(id int64) string {
	return fmt.Sprintf("member:%d", id)
}
