结合你 **AI音视频对话项目**，把「建仓库、本地拉取、创建分支、开发提交、推送、PR合并、冲突处理」全套命令+网页操作分步讲清，分**Git 命令行**（主力）+ **GitHub 网页端**（PR/合并），全程可直接照着敲。

# 前置准备
1. 已安装 Git，配置好用户名/邮箱
2. 本地已登录 GitHub（SSH 方式优先，免重复输密码）

---

# 一、第一步：GitHub 网页端 创建远程仓库
1. 登录 GitHub → 右上角 **+** → **New repository**
2. 填写配置
   - Repository name：仓库名（如 `ai-vision-chat`）
   - Description：项目简介（选填）
   - Public / Private：按需选择
   - ✅ **Add a README file**
   - ✅ **Add .gitignore**：选对应技术（Android / Node）
   - License：可选 MIT
3. 点 **Create repository**，仓库创建完成。

---

# 二、第二步：本地克隆仓库 & 初始操作
## 1. 克隆远程仓库到本地
进入仓库主页 → 点击 **Code**，复制地址（推荐 SSH）
打开终端/CMD，执行：
```bash
# 克隆仓库
git clone git@github.com:你的用户名/ai-vision-chat.git

# 进入项目文件夹
cd ai-vision-chat
```

## 2. 查看当前分支
刚克隆下来，默认在 **main（主分支）**
```bash
git branch
```
输出示例：
```
* main
```

---

# 三、第三步：创建长期开发分支 dev（团队标准流程）
规则：**所有功能不直接写在 main，先统一走 dev**

## 1. 本地创建 dev 分支，并切换过去
```bash
# 基于当前 main 新建 dev 分支，并切换到 dev
git checkout -b dev
```

## 2. 把本地 dev 推送到 GitHub 远程仓库
```bash
git push origin dev
```

现在远程仓库就有 `main` 和 `dev` 两个长期分支。

## 3. 查看远程所有分支
```bash
git branch -a
```

---

# 四、第四步：创建功能分支 feature（日常开发用）
需求：开发新功能/改 Bug，**每一个功能对应一条 feature 分支**

### 规范命名
`feature/功能名` 例：`feature/camera-mic`、`feature/ai-chat`

## 1. 每次开发前，先切回 dev、拉取最新代码（必做，防冲突）
```bash
# 切到 dev
git checkout dev

# 拉取远程 dev 最新代码
git pull origin dev
```

## 2. 新建并切换到功能分支
```bash
# 示例：创建相机麦克风功能分支
git checkout -b feature/camera-mic
```

现在你在 `feature/camera-mic` 分支，可以正常写代码。

---

# 五、第五步：代码编写 + 本地提交 + 推送到远程分支
## 1. 编写代码完成后，查看文件改动
```bash
git status
```

## 2. 将改动加入暂存区
```bash
# 所有改动文件加入暂存
git add .
```

## 3. 本地提交（必须写清晰备注）
格式：`feat: 功能描述` / `fix: 修复xxx问题`
```bash
git commit -m "feat: 完成摄像头+麦克风采集基础功能"
```

## 4. 将本地 feature 分支 推送到 GitHub 远程
```bash
git push origin feature/camera-mic
```

推送后，远程就有了这条功能分支。

---

# 六、第六步：GitHub 网页端 创建 PR（Pull Request）
作用：请求把 `feature/*` 合并到 `dev`，走代码评审。

1. 进入 GitHub 仓库主页
2. 会自动弹出 **Compare & pull request**，点击进入
3. 配置 PR 目标（重点）
   - **base**（目标分支）：选择 `dev`
   - **compare**（来源分支）：选择你刚推送的 `feature/camera-mic`
4. 填写标题、详情（改了什么、测试点）
5. 指派评审人（Reviewer），点击 **Create pull request**

### 补充规则
- CI 自动化检查、代码评审 `Approve` 通过后，才能合并
- 若提示 **conflicts**：存在代码冲突，需要本地解决再更新

---

# 七、第七步：解决代码冲突（高频场景）
当多人同时开发，分支代码不一致就会冲突。

1. 本地切到自己的 feature 分支
```bash
git checkout feature/camera-mic
```
2. 拉取 dev 最新代码，合并解决冲突
```bash
git pull origin dev
```
3. 打开冲突文件，手动修改冲突标记 `<<<<<` `=====` `>>>>>`
4. 解决完毕，重新提交、推送
```bash
git add .
git commit -m "fix: 解决与dev分支代码冲突"
git push origin feature/camera-mic
```
PR 页面会自动刷新，冲突消失。

---

# 八、第八步：合并 PR + 收尾（feature → dev）
PR 评审通过、无冲突、CI 通过后：
1. 在 PR 页面下方，选择合并方式（常用三种）
   - **Create a merge commit**：保留完整提交记录（最常用）
   - **Squash and merge**：压缩成一条提交（代码整洁）
2. 点击 **Merge pull request** → 完成合并
3. 合并后：**删除远程 feature 分支**（页面有 Delete branch 按钮，建议清理）

### 本地收尾（回到本地）
```bash
# 切回 dev
git checkout dev

# 拉取远程 dev 最新（刚合并完功能）
git pull origin dev

# 删除本地无用的 feature 分支（可选）
git branch -d feature/camera-mic
```

> 至此：**单个功能分支完整生命周期结束**。

---

# 九、第九步：迭代完成后 dev 合并到主分支 main（上线）
整轮迭代所有功能都合并到 dev、测试全部通过后，再合并到正式主分支 `main`。

## 1. 本地操作
```bash
# 切到 dev，确保代码最新
git checkout dev
git pull origin dev
```

## 2. 网页端新建 PR（dev → main）
1. 仓库主页 → New pull request
2. base 选 `main`，compare 选 `dev`
3. 填写版本/迭代说明，创建 PR
4. 评审、检查通过后，执行合并

## 3. 合并后本地同步
```bash
git checkout main
git pull origin main
```

---

# 十、紧急修复 hotfix 分支（线上Bug专用）
线上 main 出现严重 Bug，流程特殊：
1. 基于 `main` 创建修复分支
```bash
git checkout main
git pull origin main
git checkout -b hotfix/fix-crash
```
2. 修复代码 → 提交 → 推送
3. 网页提 PR：`hotfix/*` → **main**
4. 合并后，**再把修复代码同步回 dev**（保证两边一致）

---

# 十一、全套流程极简总结（背诵版）
## 1. 首次建仓+初始化分支
```
GitHub 新建仓库 → git clone → git checkout -b dev → git push origin dev
```

## 2. 日常开发标准流程（循环使用）
1. `git checkout dev` → `git pull origin dev`
2. `git checkout -b feature/xxx` 写代码
3. `git add .` → `git commit -m "备注"` → `git push origin feature/xxx`
4. GitHub 提 PR：feature → dev
5. 评审通过 → 合并PR → 删除无用分支
6. 本地切回 dev 并拉取最新

## 3. 版本上线流程
所有功能合入 dev + 测试通过 → 提 PR dev → main → 合并上线

---

# 十二、常用命令速查表（收藏）
```bash
# 查看分支
git branch

# 创建并切换分支
git checkout -b 分支名

# 切换已有分支
git checkout 分支名

# 拉取远程代码
git pull origin 分支名

# 推送本地分支到远程
git push origin 分支名

# 删除本地分支
git branch -d 分支名
```