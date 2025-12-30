package test

import (
	"fmt"
	"time"
)

// ExampleFunction demonstrates a simple function
func ExampleFunction(name string) string {
	return fmt.Sprintf("Hello, %s! Current time: %s", name, time.Now().Format(time.RFC3339))
}

// CalculateSum adds two integers
func CalculateSum(a, b int) int {
	return a + b
}

// ProcessData processes a slice of integers
func ProcessData(numbers []int) int {
	sum := 0
	for _, num := range numbers {
		sum += num
	}
	return sum
}

