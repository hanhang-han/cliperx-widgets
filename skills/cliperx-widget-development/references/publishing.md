# 工坊投稿与发布

工坊 API 使用 `https://api.cliperx.com/api/workshop`。作者通过已有灵剪账号进行浏览器授权，提交 `.cliperxwidget` 包并查看审核状态。

## 本地包投稿

```bash
node /path/to/cliperx-widgets/bin/widget.mjs login
node /path/to/cliperx-widgets/bin/widget.mjs upload /path/to/my-widget --source https://github.com/author/repository
node /path/to/cliperx-widgets/bin/widget.mjs status
node /path/to/cliperx-widgets/bin/widget.mjs status SUBMISSION_ID
```

授权时浏览器显示验证码与登录账号，确认后 CLI 保存专属工坊令牌。macOS 使用系统钥匙串，其他开发平台使用 0600 权限的本地文件。`whoami` 查看当前工坊账号，`logout` 撤销并移除令牌。`--no-open` 打印授权链接供手动打开，`--api URL` 选择明确的 HTTPS 服务或本机回环开发服务。

`upload` 校验并打包工程、创建投稿、更新元数据、上传包和提交审核，输出投稿 ID、版本、包哈希和服务端状态。`--draft` 保存草稿后停止，`submit --submission ID` 可继续提交。同版本同内容重复上传返回已有投稿；已发布版本内容变化需要递增版本号。

待审状态使用 `withdraw ID` 撤回再修改，`status ID` 显示检查结果和审核意见。需要修改的稿件在更新后重新提交。审核批准后才进入公开目录，下载地址由服务返回。

## 工坊说明

工程中的 `workshop.json` 可填写以下字段，也可使用 `--metadata FILE`。

```json
{
  "category": "clipboard",
  "tags": ["整理"],
  "readme": "选择复制的材料，点击组件开始处理。",
  "changelog": "首次发布。",
  "minAppVersion": "4.0.15",
  "feedbackURL": "https://github.com/author/repository/issues"
}
```

分类支持 clipboard、ai、productivity、system、other。标签最多八个，每个 40 字。使用说明最多 20000 字，更新记录 4000 字，最低版本采用 x.y.z。截图通过工坊网站上传，每条最多四张，每张不超过 2 MB。包的作者文字用于展示，组件归属由已登录账号确定。

## GitHub 包导入

已有 GitHub Release 工具可以继续创建公开下载包。

```bash
node /path/to/cliperx-widgets/bin/widget.mjs publish /path/to/my-widget --repo author/repository
node /path/to/cliperx-widgets/bin/widget.mjs import --entry /path/to/dist/com.author.widget.entry.json
```

导入服务校验来源、完整清单和 SHA256，然后创建投稿并提交审核。`import --draft` 只建立草稿。

## 已有 GitHub 目录 PR 流程

公开目录位于 `hanhang-han/cliperx-widgets` 的 `registry/index.json`。组件包保存在作者公开仓库的 GitHub Release，目录记录完整清单、下载地址、SHA256 和源码提交地址。

## 发布前

1. 在实际组件上运行 validate、preview 和适用的点击、离线、配置验证，生成 pack。
2. 为公开内容选择真实作者、组件 ID 和许可证，递增已发布组件的版本。
3. 将 manifest.json 和 widget.js 提交并推送到用户指定的公开 GitHub 仓库。组件目录可以位于仓库的子目录。
4. 使用 `gh auth status` 检查已有登录，沿用用户已授权的目标仓库和发布范围。

## 发布包

```bash
node /path/to/cliperx-widgets/bin/widget.mjs publish /path/to/widget --repo author/repository
```

工具会检查远端源码提交存在、组件文件已提交、目标仓库公开，生成包并上传 GitHub Release。默认标签为 `组件ID-v版本`，可以用 `--tag` 指定合法标签。已存在的 Release 包会下载校验，相同内容可安全重试，变更内容应递增组件版本。

输出包括条目文件的真实路径，例如 `dist/com.author.widget.entry.json`。以实际工具返回值为准。

## 提交到工坊

```bash
node /path/to/cliperx-widgets/bin/widget.mjs submit --entry /path/to/dist/com.author.widget.entry.json
```

工具读取公共目录、合并当前组件条目，在作者 fork 或有所有权的目录仓库中创建独立分支，提交目录修改并创建 PR。已经存在的收录 PR 会返回同一链接。

PR 应提供组件用途、源码、版本、包哈希和权限。维护者核对包与源码、在支持 组件所声明 API 版本的灵剪构建中验证后合并。合并后其他用户刷新「创意工坊」即可看到新版本。

GitHub Release 已上传表示包可下载。工坊目录 PR 已合并表示组件已经进入发现列表。报告这两项的实际状态。

## 维护者本地收录

```bash
node bin/widget.mjs catalog-add . --entry dist/com.author.widget.entry.json
git add registry/index.json
git commit -m "widget: add component"
git push origin main
```

目录条目必须使用 HTTPS GitHub 下载地址和 64 位小写 SHA256。相同 ID 和版本的包哈希保持一致。更新保留相同组件 ID，便于 App 维持实例配置和位置。
