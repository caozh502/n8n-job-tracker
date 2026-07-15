# 求职跟踪数据库 - 手动创建指南

## 在 Notion 中创建

1. 新建一个 Page，标题 "Job Recommendations"
2. 输入 `/database` → 选择 "Table" (Inline)
3. 添加以下列：

| 列名 | 类型 | 说明 |
|------|------|------|
| **Job Title** | Title (主列) | 岗位名称 |
| **Company** | Text | 公司名 |
| **Location** | Select | Munich / Remote / Berlin 等 |
| **Score** | Number | DeepSeek 匹配分 (1-10) |
| **Link** | URL | LinkedIn 岗位链接 |
| **Posted** | Date | 发布日期 |
| **Match Level** | Select | ⭐ 高度符合 / 💪 可以尝试 |
| **Industry** | Select | Automotive / MedTech / IT-Software / Industrial Automation / Logistics / Energy / Other |
| **Match Reason** | Text | DeepSeek 给的匹配理由摘要 |
| **Notes** | Text | 你的备注 |

## 创建步骤

1. 打开 https://www.notion.so/my-integrations
2. 点击 "New Integration"
3. 命名 `n8n Job Tracker`
4. 选择关联的 workspace
5. 复制 **Internal Integration Secret**（以 `ntn_` 或 `secret_` 开头）
6. 回到 Notion，在 Job Recommendations 页面右上角 `...` → **Connect to** → 选择 `n8n Job Tracker`
7. 复制页面的 URL，最后一段 32位字符就是 **Database ID**

> ⚠️ 记下 Database ID 和 API Key，后面配置 n8n 时需要。
