package models

import (
	"database/sql"
	"time"
	"tuna/database"
)

func CreateUserInfo(user *UserInfo) error {
	query := `INSERT INTO user_info_tab (name, email, phone, hobby, age, address, status, created_at, updated_at) 
	          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
	
	now := time.Now()
	_, err := database.DB.Exec(query, user.Name, user.Email, user.Phone, user.Hobby, user.Age, 
		user.Address, "pending", now, now)
	return err
}

func GetAllUsers() ([]UserInfo, error) {
	query := `SELECT id, name, email, phone, hobby, age, address, status, created_at, updated_at 
	          FROM user_info_tab ORDER BY created_at DESC`
	
	rows, err := database.DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []UserInfo
	for rows.Next() {
		var user UserInfo
		err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.Phone, &user.Hobby, 
			&user.Age, &user.Address, &user.Status, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}

	return users, rows.Err()
}

func UpdateUserStatus(id int64, status string) error {
	query := `UPDATE user_info_tab SET status = ?, updated_at = ? WHERE id = ?`
	_, err := database.DB.Exec(query, status, time.Now(), id)
	return err
}

func GetUserByID(id int64) (*UserInfo, error) {
	query := `SELECT id, name, email, phone, hobby, age, address, status, created_at, updated_at 
	          FROM user_info_tab WHERE id = ?`
	
	var user UserInfo
	err := database.DB.QueryRow(query, id).Scan(&user.ID, &user.Name, &user.Email, 
		&user.Phone, &user.Hobby, &user.Age, &user.Address, &user.Status, &user.CreatedAt, &user.UpdatedAt)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	
	return &user, nil
}

func DeleteUser(id int64) error {
	query := `DELETE FROM user_info_tab WHERE id = ?`
	_, err := database.DB.Exec(query, id)
	return err
}

