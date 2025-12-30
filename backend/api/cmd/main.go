package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	"tuna/api"
	"tuna/config"
	"tuna/database"

	"github.com/gin-gonic/gin"
)

func main() {
	// Set gin to release mode to avoid debug output issues with goc wrapper
	gin.SetMode(gin.ReleaseMode)

	cfg := config.LoadConfig()

	// Initialize database
	if err := database.InitDB(cfg); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.CloseDB()

	// Setup API server (user endpoint)
	apiRouter := api.SetupRouter()
	apiServer := &http.Server{
		Addr:    ":" + cfg.APIPort,
		Handler: apiRouter,
	}

	// Start API server
	log.Printf("API server starting on port %s", cfg.APIPort)
	go func() {
		if err := apiServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("API server failed: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down API server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := apiServer.Shutdown(ctx); err != nil {
		log.Fatal("API server forced to shutdown:", err)
	}

	log.Println("API server exited")
}

