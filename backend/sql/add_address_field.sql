-- 添加地址字段到用户信息表
-- 如果字段已存在，则不会报错（使用IF NOT EXISTS）
ALTER TABLE user_info_tab 
ADD COLUMN address VARCHAR(255) NOT NULL DEFAULT '' COMMENT '地址' AFTER age;

