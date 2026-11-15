# 发布和提交工坊

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

PR 应提供组件用途、源码、版本、包哈希和权限。维护者核对包与源码、在支持 Widget API 1 的灵剪版本中验证后合并。合并后其他用户刷新「创意工坊」即可看到新版本。

GitHub Release 已上传表示包可下载。工坊目录 PR 已合并表示组件已经进入发现列表。报告这两项的实际状态。

## 维护者本地收录

```bash
node bin/widget.mjs catalog-add . --entry dist/com.author.widget.entry.json
git add registry/index.json
git commit -m "widget: add component"
git push origin main
```

目录条目必须使用 HTTPS GitHub 下载地址和 64 位小写 SHA256。相同 ID 和版本的包哈希保持一致。更新保留相同组件 ID，便于 App 维持实例配置和位置。
