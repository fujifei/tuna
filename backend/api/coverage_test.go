package api

import (
	"testing"
)

// TestExample is a simple test function
func TestExample(t *testing.T) {
	result := 2 + 2
	if result != 4 {
		t.Errorf("Expected 4, got %d", result)
	}
}

// TestStringOperations tests string operations
func TestStringOperations(t *testing.T) {
	str := "hello"
	if len(str) != 5 {
		t.Errorf("Expected length 5, got %d", len(str))
	}
}

// TestSliceOperations tests slice operations
func TestSliceOperations(t *testing.T) {
	slice := []int{1, 2, 3, 4, 5}
	if len(slice) != 5 {
		t.Errorf("Expected length 5, got %d", len(slice))
	}
}
