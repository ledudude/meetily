# Meetily 便携版(Windows Portable)

在 exe 同级放一个空的 `portable.txt`,Meetily 就会把所有可写数据落到 `./data/` 而不是 `%APPDATA%\com.meetily.ai\`,可以直接放 U 盘、拷贝到别的机器。

## 数据布局(portable 模式)

```
meetily-portable-<version>-windows-x64/
├── meetily.exe
├── portable.txt              ← 存在即启用便携模式(内容随意)
├── README.txt
├── resources/
│   └── templates/*.json      ← 内置摘要模板
├── binaries/                 ← 可选,llama-helper / ffmpeg 等
└── data/                     ← 首次运行由 app 自动填充
    ├── meeting_minutes.sqlite
    ├── models/
    │   ├── ggml-*.bin        ← Whisper 模型
    │   ├── parakeet/         ← Parakeet 模型
    │   └── summary/          ← 内置 LLM 模型
    ├── recordings/           ← 录音文件
    ├── templates/            ← 用户自定义模板(会覆盖内置同名模板)
    └── notifications.json
```

## 优先级

数据根目录按以下顺序解析(见 `src-tauri/src/paths.rs`):

1. 环境变量 `MEETILY_DATA_DIR` 指定的绝对路径 —— 最高优先级
2. exe 同级存在 `portable.txt` —— 使用 `<exe_dir>/data/`
3. 都没有 —— 回落到 Tauri `app_data_dir()`(`%APPDATA%\com.meetily.ai\`)

## 打包

在 `frontend` 目录下:

```powershell
# 一步到位:tauri build (--bundles none) + 组装 portable 目录 + 生成 zip
pnpm run pack:portable

# 已经构建过,只想重新打包:
powershell -File scripts/pack-portable.ps1 -SkipBuild
```

产出:

- `dist/meetily-portable-<version>-windows-x64/`  展开好的便携目录
- `dist/meetily-portable-<version>-windows-x64.zip`  压缩包

## 现有用户迁移

如果之前已用非便携模式运行过,把老数据搬过来即可:

```powershell
Copy-Item "$env:APPDATA\com.meetily.ai\*" `
          ".\data\" -Recurse -Force
```

或者反过来,如果不想再用便携模式,删掉 `portable.txt` 就会回到 `%APPDATA%`。
