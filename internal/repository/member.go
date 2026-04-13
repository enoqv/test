package repository

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/enoqv/test/internal/model"
)

var ErrNotFound = errors.New("member not found")

type MemberRepository interface {
	Create(ctx context.Context, m *model.Member) error
	GetByID(ctx context.Context, id int64) (*model.Member, error)
	GetByUsername(ctx context.Context, username string) (*model.Member, error)
}

type PostgresMemberRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresMemberRepository(pool *pgxpool.Pool) *PostgresMemberRepository {
	return &PostgresMemberRepository{pool: pool}
}

func (r *PostgresMemberRepository) Create(ctx context.Context, m *model.Member) error {
	now := time.Now().UTC()
	m.CreatedAt = now
	m.UpdatedAt = now
	return r.pool.QueryRow(ctx,
		`INSERT INTO members (username, email, password_hash, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id`,
		m.Username, m.Email, m.PasswordHash, m.CreatedAt, m.UpdatedAt,
	).Scan(&m.ID)
}

func (r *PostgresMemberRepository) GetByID(ctx context.Context, id int64) (*model.Member, error) {
	m := &model.Member{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, username, email, password_hash, created_at, updated_at
		 FROM members WHERE id = $1`, id,
	).Scan(&m.ID, &m.Username, &m.Email, &m.PasswordHash, &m.CreatedAt, &m.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return m, nil
}

func (r *PostgresMemberRepository) GetByUsername(ctx context.Context, username string) (*model.Member, error) {
	m := &model.Member{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, username, email, password_hash, created_at, updated_at
		 FROM members WHERE username = $1`, username,
	).Scan(&m.ID, &m.Username, &m.Email, &m.PasswordHash, &m.CreatedAt, &m.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return m, nil
}
