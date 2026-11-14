# 源码说明

`LeiGod-OneClick.ps1` 是完整的一键脚本源码，包含补丁、样式、取色和还原逻辑。普通使用不需要 Node.js，也不需要执行本页命令。

其中压缩后的离线配色 JavaScript 由 `source/md3e-system-color-entry.js` 与固定版本的 `@material/material-color-utilities` 生成。为便于检查和修改，这里同时提供生成入口、构建脚本及依赖锁文件。

需要重新生成配色资源时，安装 Node.js 22 或更新版本，在 `source/` 目录运行：

```sh
npm ci
npm run build
```

命令会更新上一级 `LeiGod-OneClick.ps1` 中的配色资源，保留脚本的 UTF-8 BOM。只校验、不写入可运行 `node build.mjs --check`。

第三方库源码随依赖安装在 `source/node_modules/@material/material-color-utilities/`，其许可及上游地址见[第三方声明](THIRD-PARTY-NOTICES.md)。
