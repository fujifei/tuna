package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	"tuna/admin"
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

	// Setup Admin server (admin endpoint)
	adminRouter := admin.SetupRouter()
	adminServer := &http.Server{
		Addr:    ":" + cfg.AdminPort,
		Handler: adminRouter,
	}

	// Start Admin server
	log.Printf("Admin server starting on port %s", cfg.AdminPort)
	go func() {
		if err := adminServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Admin server failed: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Admin server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := adminServer.Shutdown(ctx); err != nil {
		log.Fatal("Admin server forced to shutdown:", err)
	}

	log.Println("Admin server exited")
}

