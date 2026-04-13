package cache

import (
	"context"
	"errors"
	"testing"
	"time"
)

type sample struct {
	Name string `json:"name"`
	Age  int    `json:"age"`
}

func TestMemoryCache_SetAndGet(t *testing.T) {
	ctx := context.Background()
	c := NewMemoryCache()

	want := sample{Name: "alice", Age: 30}
	if err := c.Set(ctx, "k1", want, time.Minute); err != nil {
		t.Fatalf("Set returned error: %v", err)
	}

	var got sample
	if err := c.Get(ctx, "k1", &got); err != nil {
		t.Fatalf("Get returned error: %v", err)
	}
	if got != want {
		t.Errorf("got %+v, want %+v", got, want)
	}
}

func TestMemoryCache_Miss(t *testing.T) {
	ctx := context.Background()
	c := NewMemoryCache()

	var got sample
	err := c.Get(ctx, "missing", &got)
	if !errors.Is(err, ErrCacheMiss) {
		t.Errorf("expected ErrCacheMiss, got %v", err)
	}
}

func TestMemoryCache_Expire(t *testing.T) {
	ctx := context.Background()
	c := NewMemoryCache()

	if err := c.Set(ctx, "k1", sample{Name: "bob"}, 10*time.Millisecond); err != nil {
		t.Fatalf("Set returned error: %v", err)
	}
	time.Sleep(30 * time.Millisecond)

	var got sample
	err := c.Get(ctx, "k1", &got)
	if !errors.Is(err, ErrCacheMiss) {
		t.Errorf("expected ErrCacheMiss after expiry, got %v", err)
	}
}

func TestMemoryCache_Delete(t *testing.T) {
	ctx := context.Background()
	c := NewMemoryCache()

	_ = c.Set(ctx, "k1", sample{Name: "bob"}, time.Minute)
	if err := c.Delete(ctx, "k1"); err != nil {
		t.Fatalf("Delete returned error: %v", err)
	}

	var got sample
	err := c.Get(ctx, "k1", &got)
	if !errors.Is(err, ErrCacheMiss) {
		t.Errorf("expected ErrCacheMiss after delete, got %v", err)
	}
}
