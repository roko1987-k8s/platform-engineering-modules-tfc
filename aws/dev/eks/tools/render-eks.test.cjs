// Pure in-memory regression tests. No keys, fixtures, output files or real subprocesses.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const crypto = require("node:crypto");
const YAML = require("yaml");
const root = path.resolve(__dirname, "../../../..");
const catalogPath = path.join(root, "aws/dev/eks.yaml");
const templatePath = path.join(root, "aws/dev/main.tf");
const namingPath = path.join(root, "aws/dev/eks/naming/aws.json");
const sources = {
  catalogBytes: fs.readFileSync(catalogPath),
  template: fs.readFileSync(templatePath, "utf8"),
  namingBytes: fs.readFileSync(namingPath),
};
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
// Public test-only identity and SHA; no assertion of remote provenance or approval.
const context = () => ({
  teamId: "P001",
  environment: "dev",
  sequence: 1,
  moduleSha: "a".repeat(40),
});
const selection = () => ({
  system: { size: "S", minimum: 1, desired: 1, maximum: 2 },
  user: { size: "M", minimum: 1, desired: 2, maximum: 2 },
});
function pure() {
  const module = { exports: {} };
  vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, "render-eks-pure.cjs"), "utf8"),
    {
      module,
      require: (name) => {
        assert.ok(
          ["node:crypto", "yaml"].includes(name),
          "Forbidden pure-renderer effect: " + name
        );
        return require(name);
      },
    }
  );
  return module.exports.renderPure;
}
test("pure rendering is deterministic, preserves inputs and returns the five-file contract", () => {
  const render = pure(),
    c = context(),
    s = selection();
  const before = JSON.stringify({
    c,
    s,
    catalog: sources.catalogBytes.toString(),
  });
  const a = render(c, s, sources),
    b = render(c, s, sources);
  assert.equal(JSON.stringify(a), JSON.stringify(b));
  assert.equal(
    JSON.stringify({ c, s, catalog: sources.catalogBytes.toString() }),
    before
  );
  assert.equal(a.workspace, "workspaces/P001/terraform/aws/dev/eks-01");
  assert.equal(
    Object.keys(a.files).sort().join(),
    "backend.hcl,catalog.snapshot.json,generation.json,main.tf,naming.snapshot.json"
  );
  assert.equal(a.files["naming.snapshot.json"], sources.namingBytes.toString());
  const metadata = JSON.parse(a.files["generation.json"]);
  assert.equal(metadata.status, "DRAFT_BLOCKED");
  assert.equal(metadata.networking, "pending");
  assert.equal(metadata.catalogPath, "aws/dev/eks.yaml");
  assert.equal(metadata.catalogSha256, hash(sources.catalogBytes));
  assert.equal(metadata.namingSha256, hash(sources.namingBytes));
  assert.equal(a.files["main.tf"].includes("@@"), false);
});
test("EKS references keep their subdirectories and require the supplied module SHA", () => {
  const result = pure()(context(), selection(), sources);
  const expectedPrefix =
    "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//";
  const matches = [
    ...sources.template.matchAll(/source\s*=\s*"(git::[^"]+)"/g),
  ].map((m) => m[1]);
  assert.equal(matches.length, 8);
  for (const source of matches) {
    assert.ok(source.startsWith(expectedPrefix + "aws/dev/eks/modules/"));
    const [relative, ref] = source.slice(expectedPrefix.length).split("?ref=");
    assert.equal(ref, "@@MODULE_SHA@@");
    assert.ok(fs.statSync(path.join(root, relative)).isDirectory());
    assert.ok(
      result.files["main.tf"].includes(
        source.replace("@@MODULE_SHA@@", context().moduleSha)
      )
    );
  }
  assert.equal(
    result.files["main.tf"].includes("platform-engineering-vars-tfc"),
    false
  );
  assert.equal(matches.filter((s) => s.includes("/aws/addons?")).length, 2);
});
test("all eight modules, versions, profiles and networking gates remain present", () => {
  const modules = [
    "aws/networking",
    "aws/iam",
    "aws/security-groups",
    "aws/eks",
    "aws/nodegroups",
    "aws/addons",
    "aws/observability",
    "naming",
  ];
  for (const name of modules) {
    const dir = path.join(root, "aws/dev/eks/modules", name);
    assert.ok(fs.statSync(dir).isDirectory());
    const versions = fs.readFileSync(
      path.join(dir, name === "naming" ? "terraform.tf" : "versions.tf"),
      "utf8"
    );
    assert.ok(versions.includes(">= 1.9.0, < 2.0.0"));
    if (name !== "naming") assert.ok(versions.includes("= 6.20.0"));
  }
  const catalog = YAML.parse(sources.catalogBytes.toString()).eks;
  assert.deepEqual(catalog.kubernetes.allowed_versions, ["1.36"]);
  assert.deepEqual(catalog.cluster.allowed_regions, ["us-east-1"]);
  assert.equal(catalog.nodegroups.system.sizes.S, "m7i.large");
  assert.equal(catalog.nodegroups.user.sizes.M, "m7i.2xlarge");
  assert.equal(catalog.nodegroups.limits.max_total_nodes, 4);
  assert.deepEqual(catalog.nodegroups.system.allowed_capacity_types, [
    "ON_DEMAND",
  ]);
  assert.deepEqual(catalog.nodegroups.user.allowed_capacity_types, [
    "ON_DEMAND",
  ]);
  const naming = JSON.parse(sources.namingBytes);
  assert.equal(naming.region_codes["us-east-1"], "ue1");
  const template = sources.template;
  for (const token of [
    "NETWORKING_PENDING",
    "local.networking_ready ? 1 : 0",
    "default = null",
    ">= 1.10.0, < 2.0.0",
    "= 6.20.0",
  ])
    assert.ok(template.includes(token));
  assert.equal(
    (template.match(/count\s*=\s*local.networking_ready \? 1 : 0/g) || [])
      .length,
    7
  );
  assert.equal(/module\s+"observability"/.test(template), false);
});
for (const problem of [
  "approved-network",
  "network-option",
  "extra-pool",
  "extra-group-field",
  "unknown-size",
  "unordered",
  "bool-count",
  "out-of-bounds",
  "aggregate",
  "version",
  "region",
  "invalid-sha",
  "missing-sha",
  "sequence",
  "extra-context",
]) {
  test("fails closed for " + problem, () => {
    const c = context(),
      s = selection();
    const doc = YAML.parse(sources.catalogBytes.toString());
    if (problem === "approved-network")
      doc.eks.networking.conformity = "approved";
    if (problem === "network-option")
      doc.eks.networking.approved_options.test = {};
    if (problem === "extra-pool") s.extra = { ...s.user };
    if (problem === "extra-group-field") s.user.instance_type = "forbidden";
    if (problem === "unknown-size") s.user.size = "L";
    if (problem === "unordered") s.user.desired = 3;
    if (problem === "bool-count") s.system.minimum = true;
    if (problem === "out-of-bounds") s.user.minimum = 0;
    if (problem === "aggregate") doc.eks.nodegroups.limits.max_total_nodes = 3;
    if (problem === "version") doc.eks.kubernetes.allowed_versions = ["0.0"];
    if (problem === "region") doc.eks.cluster.allowed_regions = ["invalid"];
    if (problem === "invalid-sha") c.moduleSha = "main";
    if (problem === "missing-sha") delete c.moduleSha;
    if (problem === "sequence") c.sequence = 0;
    if (problem === "extra-context") c.approved = true;
    assert.throws(() =>
      pure()(c, s, { ...sources, catalogBytes: YAML.stringify(doc) })
    );
  });
}
test("adapter defaults to no formatting; explicit formatter is mocked and leaves input unchanged", () => {
  let calls = 0;
  const module = { exports: {} };
  vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, "render-eks.cjs"), "utf8"),
    {
      module,
      __dirname,
      process: { env: {}, argv: [] },
      console,
      require: (name) => {
        if (name === "./render-eks-pure.cjs") return { renderPure: pure() };
        if (name === "node:fs") return { readFileSync: fs.readFileSync };
        if (name === "node:child_process")
          return {
            execFileSync: (_binary, args, options) => {
              calls++;
              assert.deepEqual(Array.from(args), ["fmt", "-"]);
              return options.input + "\n# mock formatter\n";
            },
          };
        if (name === "node:path") return path;
        throw new Error("Unexpected adapter import");
      },
    }
  );
  const c = context(),
    s = selection();
  const result = module.exports.render(c, s);
  assert.equal(calls, 0);
  assert.equal(JSON.stringify(result), JSON.stringify(pure()(c, s, sources)));
  const before = JSON.stringify(result);
  const formatted = module.exports.formatRendered(result);
  assert.equal(calls, 2);
  assert.equal(JSON.stringify(result), before);
  assert.notEqual(formatted.files["main.tf"], result.files["main.tf"]);
  assert.equal(
    formatted.files["generation.json"],
    result.files["generation.json"]
  );
});
