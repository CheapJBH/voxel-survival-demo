# 方块生存 · Voxel Survival Demo

用 **Godot 4.6 + godot_voxel (GDExtension v1.7x)** 做的移动端低多边形体素生存 demo。

## 玩法

- **白天**：砍树拿木头、挖石头、找浆果
- **夜晚**：敌人出现，露天会失温掉血；点个火把或者钻进洞里就安全
- **循环**：木头 → 木板 → 火把 / 石镐；打怪掉骨片 → 石剑

## 操作（触屏）

| 区域 | 作用 |
|---|---|
| 左半屏 | 浮动摇杆走路 |
| 右半屏 | 拖动转视角 |
| 右下 跳 / 挖 / 填 | 跳跃、按住挖掘（有进度）、放置 |
| 底部快捷栏 | 点格子切换手持物品 |
| 右上「合」 | 打开合成面板，点配方即合成 |

PC 调试：WASD 走、空格跳、右键拖动看、左键按住挖、F 切换、滚轮切换物品。

## 已实现

- 体素地形（Transvoxel），可挖可填，LOD 4 层 + 远处雾化
- 第一人称角色：重力、碰撞、跳跃（长按连跳）、贴地吸附、卡住自救
- 20 分钟昼夜循环，太阳/月亮圆盘随时段升降，夜里变暗
- 生命 / 饥饿：饥饿见底掉血、坠落伤害、死亡掉一半背包
- 背包 8 格 + 快捷栏 + 物品名显示 + 等距立方体图标
- 挖掘耗时（草 0.35s / 土 0.5s / 石 1s / 硬岩 1.6s，有石镐 ×0.55）+ 破碎粒子
- 合成：木板 / 火把 / 石镐 / 石剑 / 烤浆果
- 敌人：天黑后刷新，追人咬人；白天消失；打死掉骨片
- 火把：真实光源，夜里 9.5m 内不掉血
- 存档：体素改动进 VoxelStreamRegionFiles，玩家状态进 user://player.json，每 30 秒 + 切后台自动存
- 开始界面 / 加载提示

## 依赖

1. **Godot 4.6.3**（必须 4.5+，需要 get_godot_version2 接口）
2. **godot_voxel GDExtension v1.7x**
   - 下载：https://github.com/Zylann/godot_voxel/releases/tag/v1.7x
   - 解压后把 addons/zylann.voxel/ 放到本项目根目录（本仓库不含其中的 .so，体积太大）
3. Android 导出：Android SDK（platform 34+ / build-tools 36）+ JDK 21
4. 项目设置需开启 rendering/textures/vram_compression/import_etc2_astc=true（已在 project.godot 里）

## 导出 APK

```
xvfb-run -a ./Godot_v4.6.3-stable_linux.x86_64 --path . --export-debug "Android" build/voxel-demo.apk
```

Android 预设见 export_presets.cfg（使用 use_gradle_build=false + 官方模板）。

## 音乐

audio/bgm.mp3 未包含在仓库里，自行放一首即可（缺失时静音运行，不会报错）。

## 已知问题

- Transvoxel 的 LOD 交界处会有细小的台阶（官方文档描述的 sharp little steps），已用雾和更大的 LOD0 范围缓解
- 地形碰撞体是异步生成的，极端情况下快速移动仍可能短暂穿透（有兜底抬升）
