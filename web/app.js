document.body.innerHTML = `
  <header class="topbar">
    <div class="brand">
      <div class="brand-kicker">网络互惠</div>
      <h1>合作临界条件计算器</h1>
      <p class="brand-note">用于加权无向网络与异质决策机制的本地计算工具。</p>
    </div>
    <label class="api-control">
      接口地址
      <input id="apiUrl" value="/api/compute" autocomplete="off">
    </label>
  </header>

  <main class="shell">
    <section class="panel">
      <div class="panel-head">
        <div class="panel-title">
          <h2>模型设定</h2>
          <p class="panel-subtitle">选择示例或手动输入网络与决策参数。</p>
        </div>
        <div class="actions">
          <button class="secondary" id="showRequest" type="button">预览请求</button>
          <button class="primary" id="compute" type="button">
            <span>计算</span>
            <span class="button-spinner" aria-hidden="true"></span>
          </button>
        </div>
      </div>

      <div class="content">
        <div class="example-board">
          <label class="field">
            <span class="field-label">输入模式 / 示例</span>
            <select id="exampleSelect"></select>
          </label>
          <div id="exampleDescription" class="example-description"></div>
        </div>

        <label class="field">
          <span class="field-label">邻接矩阵</span>
          <span class="hint">请输入对称加权矩阵。第 i 行第 j 列的元素 a_ij 表示个体 i 与个体 j 的交互强度。</span>
          <textarea id="adjacencyMatrix" spellcheck="false"></textarea>
        </label>

        <div class="field-row">
          <label class="field">
            <span class="field-label">试错概率 PTE</span>
            <input id="pte" value="0.2, 0.3, 0.4" autocomplete="off">
            <span class="hint">个体以 PTE 的概率独自试错，或以 1-PTE 的概率模仿优秀邻居。这用最简单的结构描述了人类在位置环境下决策的主导方式。</span>
          </label>
          <label class="field">
            <span class="field-label">决策机制 MU</span>
            <input id="mu" value="1, 0, 2" autocomplete="off">
            <span class="hint">MU 描述个体试错时的价值取向。MU=0 表示期望收益机制；有限正值越小越重视短期收益，越大越重视长期收益；MU=∞ 表示漫无目的随机试错。</span>
          </label>
        </div>

        <details class="details">
          <summary>计算精度</summary>
          <div class="details-body">
            <p class="hint">max_iter_tau 是 neutral IIS 与 cross-time IIS 概率的最大迭代次数。conv_tol_tau 是最大更新误差的停止阈值。迭代次数越大、阈值越小，通常更精确但更慢。</p>
            <div class="field-row">
              <label class="field">
                <span class="field-label">max_iter_tau</span>
                <input id="maxIterTau" value="500" autocomplete="off">
              </label>
              <label class="field">
                <span class="field-label">conv_tol_tau</span>
                <input id="convTolTau" value="1e-10" autocomplete="off">
              </label>
            </div>
          </div>
        </details>

        <div id="status" class="status" role="status" aria-live="polite"></div>
        <div id="inlineComputing" class="inline-computing" hidden>
          <div class="mini-network" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
          </div>
          <div>
            <strong>正在计算临界条件</strong>
            <p>正在转换邻接矩阵、迭代 IIS 概率并评估弱选择阈值。</p>
          </div>
        </div>
      </div>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div class="panel-title">
          <h2>计算结果</h2>
          <p class="panel-subtitle">临界条件、收敛状态与当前网络结构。</p>
        </div>
        <span id="resultState" class="eyebrow">待计算</span>
      </div>

      <div class="content">
        <div id="computingCard" class="computing-card" hidden>
          <svg class="compute-animation" viewBox="0 0 132 92" aria-hidden="true">
            <line class="pulse-edge" x1="28" y1="62" x2="66" y2="22"></line>
            <line class="pulse-edge" x1="66" y1="22" x2="104" y2="62"></line>
            <line class="pulse-edge" x1="28" y1="62" x2="104" y2="62"></line>
            <circle class="pulse-node" cx="28" cy="62" r="10"></circle>
            <circle class="pulse-node" cx="66" cy="22" r="10"></circle>
            <circle class="pulse-node" cx="104" cy="62" r="10"></circle>
          </svg>
          <div class="computing-copy">
            <strong>正在计算临界条件</strong>
            <span>正在转换邻接矩阵、求解 neutral IIS 概率，并评估弱选择阈值。</span>
          </div>
        </div>

        <div class="metric-grid">
          <div class="metric">
            <span>临界 b/c</span>
            <strong id="bcStar">-</strong>
            <small>当 b/c 高于该阈值时，合作更容易被选择所偏好。</small>
          </div>
          <div class="metric">
            <span>计算收敛</span>
            <strong id="converged">-</strong>
            <small>IIS 迭代是否达到停止条件。</small>
          </div>
          <div class="metric">
            <span>计算误差</span>
            <strong id="tauErr">-</strong>
            <small>tau 固定点迭代的最终误差。</small>
          </div>
        </div>

        <div class="meaning">
          在捐赠博弈中，合作者支付成本 c，为互动对象提供收益 b；背叛者既不支付成本，也不提供收益。本工具计算弱选择条件下的临界值 (b/c)*。临界值越小，说明在当前网络与决策机制下，合作越容易占优。
        </div>

        <div class="result-layout">
          <div class="viz-block">
            <div class="viz-title">
              <h3>网络可视化</h3>
              <span class="hint">由邻接矩阵生成</span>
            </div>
            <div id="networkViz" class="network-viz"></div>
            <div id="parameterSummary" class="param-summary"></div>
          </div>

          <div class="viz-block">
            <div class="viz-title">
              <h3>矩阵热图</h3>
              <span class="hint">颜色越深，交互强度越高</span>
            </div>
            <div id="heatmap" class="heatmap"></div>
            <div class="game-card">
              <div>
                <h3>捐赠博弈收益矩阵</h3>
                <p class="microcopy">合作者支付成本 c，为对方提供收益 b；背叛者不支付成本，也不提供收益。</p>
              </div>
              <div class="payoff-matrix" aria-label="捐赠博弈收益矩阵">
                <div></div>
                <div>对方合作 C</div>
                <div>对方背叛 D</div>
                <div>自己合作 C</div>
                <div>b-c</div>
                <div>-c</div>
                <div>自己背叛 D</div>
                <div>b</div>
                <div>0</div>
              </div>
            </div>
          </div>
        </div>

        <details id="detailsOutput" class="details">
          <summary>接口摘要</summary>
          <div class="details-body">
            <pre id="output">{}</pre>
          </div>
        </details>
      </div>
    </section>
  </main>
`;

const NODE_COUNT = 40;
const CUSTOM_SCENARIO_ID = "custom-input";
const customScenario = {
  id: CUSTOM_SCENARIO_ID,
  name: "自由输入",
  description: "手动编辑邻接矩阵、PTE 与 MU。MU 可以输入 0、正整数或 ∞；计算时 ∞ 会转换为代码中的负值，用来表示随机试错。"
};

function createMatrix(size) {
  return Array.from({ length: size }, () => Array(size).fill(0));
}

function connect(matrix, i, j, weight = 1) {
  matrix[i - 1][j - 1] = weight;
  matrix[j - 1][i - 1] = weight;
}

function ringLatticeExample() {
  const matrix = createMatrix(NODE_COUNT);

  for (let i = 1; i <= NODE_COUNT; i += 1) {
    connect(matrix, i, (i % NODE_COUNT) + 1, 1.0);
    connect(matrix, i, ((i + 1) % NODE_COUNT) + 1, 0.55);
  }

  return {
    id: "local-neighborhood",
    name: "局部邻里：空间嵌入互动",
    description: "40 个体的局部邻里网络，每个个体主要与附近位置互动。PTE 处于中低水平，MU 取较短有限值，展示有限局部适应和短期反馈主导的场景。",
    matrix,
    PTE: Array.from({ length: NODE_COUNT }, (_, index) => (index % 5 === 0 ? 0.35 : 0.18)),
    mu: Array.from({ length: NODE_COUNT }, (_, index) => (index % 4 === 0 ? 0 : 2))
  };
}

function corePeripheryExample() {
  const matrix = createMatrix(NODE_COUNT);
  const core = Array.from({ length: 8 }, (_, index) => index + 1);

  for (let a = 0; a < core.length; a += 1) {
    for (let b = a + 1; b < core.length; b += 1) {
      connect(matrix, core[a], core[b], 1.25);
    }
  }

  for (let i = 9; i <= NODE_COUNT; i += 1) {
    const hub = ((i - 9) % core.length) + 1;
    connect(matrix, i, hub, 1.0);
    connect(matrix, i, ((hub % core.length) + 1), 0.35);
    if (i < NODE_COUNT && (i - 9) % 4 !== 3) {
      connect(matrix, i, i + 1, 0.45);
    }
  }

  return {
    id: "core-periphery",
    name: "核心边缘：可见核心与外围学习者",
    description: "少数核心节点高度连接，并向外围个体扩散行为。核心节点更倾向模仿既有高收益邻居，外围节点更常试错，其中部分个体采用 ∞ 表示随机试错。",
    matrix,
    PTE: Array.from({ length: NODE_COUNT }, (_, index) => (index < 8 ? 0.08 : 0.42)),
    mu: Array.from({ length: NODE_COUNT }, (_, index) => (index < 8 ? 4 : index % 6 === 0 ? "∞" : 2))
  };
}

function modularBridgeExample() {
  const matrix = createMatrix(NODE_COUNT);

  for (let community = 0; community < 4; community += 1) {
    const start = community * 10 + 1;
    const end = start + 9;
    for (let i = start; i <= end; i += 1) {
      connect(matrix, i, i === end ? start : i + 1, 1.0);
      connect(matrix, i, start + ((i - start + 2) % 10), 0.5);
    }
  }

  connect(matrix, 5, 16, 0.35);
  connect(matrix, 15, 26, 0.35);
  connect(matrix, 25, 36, 0.35);
  connect(matrix, 35, 6, 0.35);

  return {
    id: "modular-bridges",
    name: "社群桥接：群体边界位置",
    description: "四个紧密社群由弱桥接边连接。多数成员依赖局部模仿，边界位置更频繁试错，并通过更长 MU 比较跨群体互动后的收益。",
    matrix,
    PTE: Array.from({ length: NODE_COUNT }, (_, index) => ([4, 14, 24, 34].includes(index) ? 0.55 : 0.16)),
    mu: Array.from({ length: NODE_COUNT }, (_, index) => ([4, 14, 24, 34].includes(index) ? 5 : index % 10 === 0 ? 0 : 1))
  };
}

const examples = [
  ringLatticeExample(),
  corePeripheryExample(),
  modularBridgeExample()
];
const scenarios = [customScenario, ...examples];

const fields = {
  apiUrl: document.querySelector("#apiUrl"),
  exampleSelect: document.querySelector("#exampleSelect"),
  exampleDescription: document.querySelector("#exampleDescription"),
  adjacencyMatrix: document.querySelector("#adjacencyMatrix"),
  pte: document.querySelector("#pte"),
  mu: document.querySelector("#mu"),
  maxIterTau: document.querySelector("#maxIterTau"),
  convTolTau: document.querySelector("#convTolTau"),
  status: document.querySelector("#status"),
  output: document.querySelector("#output"),
  detailsOutput: document.querySelector("#detailsOutput"),
  computingCard: document.querySelector("#computingCard"),
  inlineComputing: document.querySelector("#inlineComputing"),
  bcStar: document.querySelector("#bcStar"),
  converged: document.querySelector("#converged"),
  tauErr: document.querySelector("#tauErr"),
  networkViz: document.querySelector("#networkViz"),
  heatmap: document.querySelector("#heatmap"),
  parameterSummary: document.querySelector("#parameterSummary"),
  resultState: document.querySelector("#resultState"),
  compute: document.querySelector("#compute")
};

function setStatus(message, isError = false) {
  fields.status.textContent = message;
  fields.status.classList.toggle("error", isError);
}

function setLoading(isLoading) {
  document.body.classList.toggle("is-computing", isLoading);
  fields.compute.disabled = isLoading;
  fields.computingCard.hidden = !isLoading;
  fields.inlineComputing.hidden = !isLoading;
  if (isLoading) {
    fields.resultState.textContent = "计算中";
  }
}

function parseNumber(value, label) {
  const parsed = Number(String(value).trim());

  if (!Number.isFinite(parsed)) {
    throw new Error(`${label} 必须是有限数字。`);
  }

  return parsed;
}

function parseInteger(value, label) {
  const parsed = Number(String(value).trim());

  if (!Number.isInteger(parsed)) {
    throw new Error(`${label} 必须是整数。`);
  }

  return parsed;
}

function parseMu(value, label) {
  const normalized = String(value).trim().toLowerCase();

  if (["∞", "inf", "+inf", "infinity", "+infinity"].includes(normalized)) {
    return -1;
  }

  const parsed = parseInteger(value, label);
  if (parsed < 0) {
    throw new Error(`${label} 不能为负数；如需表示随机试错，请输入 ∞。`);
  }
  return parsed;
}

function parseVector(value, label, parser) {
  const parts = value
    .split(/[,\s，]+/)
    .map((part) => part.trim())
    .filter(Boolean);

  if (parts.length === 0) {
    throw new Error(`${label} 不能为空。`);
  }

  return parts.map((part, index) => parser(part, `${label}[${index + 1}]`));
}

function parseMatrix(value) {
  const rows = value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (rows.length === 0) {
    throw new Error("邻接矩阵不能为空。");
  }

  const matrix = rows.map((line, rowIndex) => {
    const parts = line
      .split(/[,\s，]+/)
      .map((part) => part.trim())
      .filter(Boolean);

    if (parts.length !== rows.length) {
      throw new Error("邻接矩阵必须是方阵。");
    }

    return parts.map((part, colIndex) => {
      const value = parseNumber(part, `a[${rowIndex + 1},${colIndex + 1}]`);
      if (value < 0) {
        throw new Error("邻接矩阵权重必须非负。");
      }
      return value;
    });
  });

  for (let i = 0; i < matrix.length; i += 1) {
    const degree = matrix[i].reduce((sum, value) => sum + value, 0);
    if (degree <= 0) {
      throw new Error(`节点 ${i + 1} 的加权度为 0。`);
    }

    for (let j = i + 1; j < matrix.length; j += 1) {
      if (Math.abs(matrix[i][j] - matrix[j][i]) > 1e-12) {
        throw new Error("无向网络的邻接矩阵必须对称。");
      }
    }
  }

  return matrix;
}

function matrixToEdgeSeq(matrix) {
  const edgeSeq = [];

  matrix.forEach((row, rowIndex) => {
    row.forEach((weight, colIndex) => {
      if (weight !== 0) {
        edgeSeq.push([rowIndex + 1, colIndex + 1, weight]);
      }
    });
  });

  return edgeSeq;
}

function buildPayload() {
  const matrix = parseMatrix(fields.adjacencyMatrix.value);
  const PTE = parseVector(fields.pte.value, "PTE", parseNumber);
  const mu = parseVector(fields.mu.value, "mu", parseMu);
  const maxIterTau = parseInteger(fields.maxIterTau.value, "max_iter_tau");
  const convTolTau = parseNumber(fields.convTolTau.value, "conv_tol_tau");

  if (PTE.length !== matrix.length) {
    throw new Error(`PTE 的长度必须等于 N = ${matrix.length}。`);
  }

  if (mu.length !== matrix.length) {
    throw new Error(`MU 的长度必须等于 N = ${matrix.length}。`);
  }

  if (mu.some((value) => value > matrix.length)) {
    throw new Error(`有限 MU 必须位于 [0,N]，当前 N = ${matrix.length}。`);
  }

  if (PTE.some((value) => value < 0 || value > 1)) {
    throw new Error("PTE 的每个值必须位于 [0,1]。");
  }

  if (maxIterTau < 1) {
    throw new Error("max_iter_tau 必须为正整数。");
  }

  if (convTolTau <= 0) {
    throw new Error("conv_tol_tau 必须为正数。");
  }

  return {
    adjacency_matrix: matrix,
    PTE,
    mu,
    max_iter_tau: maxIterTau,
    conv_tol_tau: convTolTau
  };
}

function formatNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "-";
  }

  const numeric = Number(value);

  if (!Number.isFinite(numeric)) {
    return String(value);
  }

  const absolute = Math.abs(numeric);
  if (absolute !== 0 && (absolute >= 10000 || absolute < 0.0001)) {
    return numeric.toExponential(4);
  }

  return Number(numeric.toPrecision(7)).toString();
}

function formatMu(value) {
  return value < 0 ? "∞" : String(value);
}

function matrixToString(matrix) {
  return matrix.map((row) => row.map(formatNumber).join(", ")).join("\n");
}

function vectorToString(values) {
  return values.map((value) => (typeof value === "string" ? value : formatNumber(value))).join(", ");
}

function showJson(value) {
  fields.output.textContent = JSON.stringify(value, null, 2);
}

function publicResult(result) {
  if ("bc_star" in result || "tau_converged" in result || "tau_err" in result) {
    return {
      critical_bc: result.bc_star,
      computation_converged: result.tau_converged,
      computation_error: result.tau_err
    };
  }

  return result;
}

function showMetrics(value) {
  fields.bcStar.textContent = formatNumber(value.bc_star);
  fields.converged.textContent = value.tau_converged === undefined ? "-" : String(value.tau_converged);
  fields.tauErr.textContent = formatNumber(value.tau_err);
}

function makeSvgElement(name, attrs = {}) {
  const element = document.createElementNS("http://www.w3.org/2000/svg", name);
  Object.entries(attrs).forEach(([key, value]) => element.setAttribute(key, value));
  return element;
}

function renderEmptyVisualization(message) {
  fields.networkViz.innerHTML = "";
  const empty = document.createElement("div");
  empty.className = "meaning";
  empty.textContent = message;
  fields.networkViz.append(empty);
  fields.heatmap.innerHTML = "";
  fields.parameterSummary.innerHTML = "";
}

function renderNetwork(matrix) {
  fields.networkViz.innerHTML = "";

  const size = 420;
  const center = size / 2;
  const radius = Math.min(150, 62 + matrix.length * 16);
  const svg = makeSvgElement("svg", {
    viewBox: `0 0 ${size} ${size}`,
    role: "img",
    "aria-label": "由邻接矩阵生成的网络可视化"
  });

  const weights = [];
  for (let i = 0; i < matrix.length; i += 1) {
    for (let j = i + 1; j < matrix.length; j += 1) {
      if (matrix[i][j] > 0) {
        weights.push(matrix[i][j]);
      }
    }
  }
  const maxWeight = Math.max(1, ...weights);
  const positions = matrix.map((_, index) => {
    const angle = -Math.PI / 2 + (2 * Math.PI * index) / matrix.length;
    return {
      x: center + radius * Math.cos(angle),
      y: center + radius * Math.sin(angle)
    };
  });

  for (let i = 0; i < matrix.length; i += 1) {
    for (let j = i + 1; j < matrix.length; j += 1) {
      const weight = matrix[i][j];
      if (weight <= 0) {
        continue;
      }

      const start = positions[i];
      const end = positions[j];
      const width = 1.5 + 5 * (weight / maxWeight);
      const opacity = 0.24 + 0.48 * (weight / maxWeight);

      svg.append(
        makeSvgElement("line", {
          class: "edge",
          x1: start.x,
          y1: start.y,
          x2: end.x,
          y2: end.y,
          "stroke-width": width,
          opacity
        })
      );

      if (matrix.length <= 8) {
        const label = makeSvgElement("text", {
          class: "weight-label",
          x: (start.x + end.x) / 2,
          y: (start.y + end.y) / 2 - 5
        });
        label.textContent = formatNumber(weight);
        svg.append(label);
      }
    }
  }

  positions.forEach((position, index) => {
    const nodeRadius = matrix.length > 24 ? 9 : 18;
    svg.append(
      makeSvgElement("circle", {
        class: "node",
        cx: position.x,
        cy: position.y,
        r: nodeRadius
      })
    );

    if (matrix.length <= 24) {
      const label = makeSvgElement("text", {
        class: "node-label",
        x: position.x,
        y: position.y
      });
      label.textContent = String(index + 1);
      svg.append(label);
    }
  });

  fields.networkViz.append(svg);
}

function renderHeatmap(matrix) {
  fields.heatmap.innerHTML = "";
  const grid = document.createElement("div");
  grid.className = "heatmap-grid";
  grid.classList.toggle("heatmap-grid-compact", matrix.length > 12);
  grid.style.gridTemplateColumns = `repeat(${matrix.length}, minmax(${matrix.length > 12 ? "6px" : "28px"}, 1fr))`;

  const maxWeight = Math.max(1, ...matrix.flat());
  matrix.forEach((row, rowIndex) => {
    row.forEach((weight, colIndex) => {
      const ratio = weight / maxWeight;
      const cell = document.createElement("div");
      cell.className = "heat-cell";
      cell.title = `a[${rowIndex + 1},${colIndex + 1}] = ${weight}`;
      cell.textContent = matrix.length > 12 ? "" : formatNumber(weight);
      cell.style.backgroundColor =
        weight === 0
          ? "oklch(96.5% 0.01 155)"
          : `oklch(${92 - ratio * 38}% ${0.035 + ratio * 0.08} 178)`;
      cell.style.color = ratio > 0.58 ? "oklch(98% 0.005 150)" : "var(--text)";
      grid.append(cell);
    });
  });

  const note = document.createElement("p");
  note.className = "axis-note";
  note.textContent = "行表示个体 i，列表示个体 j。由于当前模型使用无向网络，因此 a_ij = a_ji。";

  fields.heatmap.append(grid, note);
}

function renderParameterSummary(matrix) {
  fields.parameterSummary.innerHTML = "";
  const PTE = parseVector(fields.pte.value, "PTE", parseNumber);
  const mu = parseVector(fields.mu.value, "mu", parseMu);
  const degrees = matrix.map((row) => row.reduce((sum, value) => sum + value, 0));
  const items = [
    ["N", String(matrix.length)],
    ["加权度", degrees.map(formatNumber).join(", ")],
    ["PTE", PTE.map(formatNumber).join(", ")],
    ["决策机制 MU", mu.map(formatMu).join(", ")]
  ];

  items.forEach(([label, value]) => {
    const chip = document.createElement("div");
    chip.className = "param-chip";

    const labelNode = document.createElement("span");
    labelNode.textContent = label;

    const valueNode = document.createElement("strong");
    valueNode.textContent = value;

    chip.append(labelNode, valueNode);
    fields.parameterSummary.append(chip);
  });
}

function updatePreview() {
  try {
    const matrix = parseMatrix(fields.adjacencyMatrix.value);
    renderNetwork(matrix);
    renderHeatmap(matrix);
    renderParameterSummary(matrix);
  } catch (error) {
    renderEmptyVisualization(error.message);
  }
}

function setCustomMode() {
  fields.exampleSelect.value = CUSTOM_SCENARIO_ID;
  fields.exampleDescription.textContent = customScenario.description;
}

function loadExample(exampleId = fields.exampleSelect.value) {
  if (exampleId === CUSTOM_SCENARIO_ID) {
    setCustomMode();
    updatePreview();
    return;
  }

  const selected = examples.find((item) => item.id === exampleId) ?? examples[0];

  fields.exampleSelect.value = selected.id;
  fields.exampleDescription.textContent = selected.description;
  fields.adjacencyMatrix.value = matrixToString(selected.matrix);
  fields.pte.value = vectorToString(selected.PTE);
  fields.mu.value = selected.mu.map((value) => (value === "∞" ? "∞" : formatMu(value))).join(", ");
  fields.maxIterTau.value = "500";
  fields.convTolTau.value = "1e-10";
  showJson({});
  showMetrics({});
  setStatus("");
  fields.resultState.textContent = "待计算";
  updatePreview();
}

scenarios.forEach((item) => {
  const option = document.createElement("option");
  option.value = item.id;
  option.textContent = item.name;
  fields.exampleSelect.append(option);
});

fields.exampleSelect.addEventListener("change", () => loadExample());

document.querySelector("#showRequest").addEventListener("click", () => {
  try {
    const payload = buildPayload();
    const preview = {
      ...payload,
      derived_edge_seq: matrixToEdgeSeq(payload.adjacency_matrix)
    };
    showJson(preview);
    fields.detailsOutput.open = true;
    setStatus("请求有效。");
  } catch (error) {
    setStatus(error.message, true);
  }
});

document.querySelector("#compute").addEventListener("click", async () => {
  try {
    const payload = buildPayload();
    showJson(publicResult(payload));
    setStatus("正在计算临界条件...");
    setLoading(true);

    const response = await fetch(fields.apiUrl.value.trim(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    const text = await response.text();
    let result;

    try {
      result = text ? JSON.parse(text) : {};
    } catch {
      result = { raw: text };
    }

    if (!response.ok) {
      throw new Error(result.error || `HTTP ${response.status}`);
    }

    const cleanResult = publicResult(result);
    showJson(cleanResult);
    showMetrics(result);
    fields.resultState.textContent = "已完成";
    setStatus("计算完成。");
  } catch (error) {
    showMetrics({});
    fields.resultState.textContent = "需检查输入";
    setStatus(error.message, true);
  } finally {
    setLoading(false);
  }
});

[
  fields.adjacencyMatrix,
  fields.pte,
  fields.mu
].forEach((field) => {
  field.addEventListener("input", () => {
    setCustomMode();
    updatePreview();
  });
});

loadExample(examples[0].id);
