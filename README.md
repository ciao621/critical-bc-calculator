# Critical b/c Calculator

一个用于计算异质网络互惠临界条件 `Critical b/c` 的网页计算器。

项目把 Julia 数学计算代码保留为核心，浏览器页面只负责输入、可视化和结果展示。用户可以输入无向加权网络的邻接矩阵、个体的 `PTE` 和决策机制参数 `MU`，然后通过后端调用 Julia 计算临界 `b/c`。

## 功能

- 输入对称加权邻接矩阵。
- 支持三个 40 节点示例网络和自由输入。
- 支持 `MU = ∞` 表示随机试错。
- 可视化网络结构和矩阵热图。
- 输出 `Critical b/c`、计算收敛状态和计算误差。

## 本地运行

需要本机安装 Julia 和 Python。

```powershell
python server\compute_server.py
```

然后打开：

```text
http://127.0.0.1:8080/
```

如果 Julia 不在系统 `PATH` 中，可以设置 `JULIA_EXE`：

```powershell
$env:JULIA_EXE="C:\path\to\julia.exe"
python server\compute_server.py
```

## 测试

```powershell
julia --project=. -e "using Pkg; Pkg.test()"
```

## 免费部署

项目已包含 Render 免费部署所需的 `Dockerfile` 和 `render.yaml`。部署说明见：

[docs/deploy-render-free.md](docs/deploy-render-free.md)

免费实例可能会在空闲后休眠，首次访问和首次计算会比较慢。
