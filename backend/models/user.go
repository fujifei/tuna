package models

import "time"

type UserInfo struct {
	ID          int64     `json:"id" db:"id"`
	Name        string    `json:"name" db:"name"`
	Email       string    `json:"email" db:"email"`
	Phone       string    `json:"phone" db:"phone"`
	Hobby       string    `json:"hobby" db:"hobby"`
	Age         int       `json:"age" db:"age"`
	Address     string    `json:"address" db:"address"`
	Status      string    `json:"status" db:"status"` // pending, approved, rejected
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time `json:"updated_at" db:"updated_at"`
}

type CreateUserRequest struct {
	Name    string `json:"name" binding:"required"`
	Email   string `json:"email" binding:"required,email"`
	Phone   string `json:"phone" binding:"required"`
	Hobby   string `json:"hobby" binding:"required"`
	Age     int    `json:"age" binding:"required,min=1,max=150"`
	Address string `json:"address" binding:"required"`
}

type UpdateStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=approved rejected"`
}

