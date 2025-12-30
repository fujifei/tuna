package api

import (
	"net/http"
	"tuna/models"

	"github.com/gin-gonic/gin"
)

func SetupRouter() *gin.Engine {
	router := gin.Default()

	// CORS middleware
	router.Use(func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		if origin != "" {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		} else {
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		}
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Type")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	})

	router.POST("/api/submit", submitUserInfo)
	router.GET("/api/health", healthCheck)

	return router
}

func submitUserInfo(c *gin.Context) {
	var req models.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := &models.UserInfo{
		Name:    req.Name,
		Email:   req.Email,
		Phone:   req.Phone,
		Hobby:   req.Hobby,
		Age:     req.Age,
		Address: req.Address,
	}

	if err := models.CreateUserInfo(user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save user info"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "User info submitted successfully",
		"id":      user.ID,
	})
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
