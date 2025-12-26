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
	"tuna/api"
	"tuna/config"
	"tuna/database"
)

func main() {
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

	// Setup Admin server (admin endpoint)
	adminRouter := admin.SetupRouter()
	adminServer := &http.Server{
		Addr:    ":" + cfg.AdminPort,
		Handler: adminRouter,
	}

	// Start API server
	go func() {
		log.Printf("API server starting on port %s", cfg.APIPort)
		if err := apiServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("API server failed: %v", err)
		}
	}()

	// Start Admin server
	go func() {
		log.Printf("Admin server starting on port %s", cfg.AdminPort)
		if err := adminServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Admin server failed: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the servers
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down servers...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := apiServer.Shutdown(ctx); err != nil {
		log.Fatal("API server forced to shutdown:", err)
	}

	if err := adminServer.Shutdown(ctx); err != nil {
		log.Fatal("Admin server forced to shutdown:", err)
	}

	log.Println("Servers exited")
}

