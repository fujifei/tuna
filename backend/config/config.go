package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	APIPort    string
	AdminPort  string
}

type ConfigFile struct {
	Database struct {
		Host     string `yaml:"host"`
		Port     string `yaml:"port"`
		User     string `yaml:"user"`
		Password string `yaml:"password"`
		Name     string `yaml:"name"`
	} `yaml:"database"`
	Ports struct {
		API   string `yaml:"api"`
		Admin string `yaml:"admin"`
	} `yaml:"ports"`
	GOC struct {
		WrapperPort string `yaml:"wrapper_port"`
		RabbitMQURL string `yaml:"rabbitmq_url"`
	} `yaml:"goc"`
	GOCBuild struct {
		SourceDir string `yaml:"source_dir"`
	} `yaml:"goc_build"`
}

func LoadConfig() *Config {
	cfg := &Config{}

	// 尝试从配置文件加载
	configPath := getConfigPath()
	if configPath != "" {
		if fileCfg, err := loadFromFile(configPath); err == nil {
			cfg.DBHost = getEnv("DB_HOST", fileCfg.Database.Host)
			cfg.DBPort = getEnv("DB_PORT", fileCfg.Database.Port)
			cfg.DBUser = getEnv("DB_USER", fileCfg.Database.User)
			cfg.DBPassword = getEnv("DB_PASSWORD", fileCfg.Database.Password)
			cfg.DBName = getEnv("DB_NAME", fileCfg.Database.Name)
			cfg.APIPort = getEnv("API_PORT", fileCfg.Ports.API)
			cfg.AdminPort = getEnv("ADMIN_PORT", fileCfg.Ports.Admin)
			return cfg
		}
	}

	// 如果配置文件不存在或读取失败，使用默认值
	cfg.DBHost = getEnv("DB_HOST", "127.0.0.1")
	cfg.DBPort = getEnv("DB_PORT", "6666")
	cfg.DBUser = getEnv("DB_USER", "agile")
	cfg.DBPassword = getEnv("DB_PASSWORD", "agile")
	cfg.DBName = getEnv("DB_NAME", "tuna")
	cfg.APIPort = getEnv("API_PORT", "8812")
	cfg.AdminPort = getEnv("ADMIN_PORT", "8813")

	return cfg
}

func getConfigPath() string {
	// 首先检查环境变量
	if path := os.Getenv("CONFIG_PATH"); path != "" {
		return path
	}

	// 尝试在backend目录下查找config.yaml
	// 获取当前工作目录
	wd, err := os.Getwd()
	if err != nil {
		return ""
	}

	// 尝试多个可能的路径
	paths := []string{
		filepath.Join(wd, "config.yaml"),
		filepath.Join(wd, "backend", "config.yaml"),
		filepath.Join(filepath.Dir(wd), "backend", "config.yaml"),
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	return ""
}

func loadFromFile(path string) (*ConfigFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg ConfigFile
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func (c *Config) GetDSN() string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		c.DBUser, c.DBPassword, c.DBHost, c.DBPort, c.DBName)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
