// Pure draft rendering. No filesystem, subprocess, network or Terraform CLI.
const crypto = require("node:crypto");
const YAML = require("yaml");
const digest = (data) => crypto.createHash("sha256").update(data).digest("hex");
const fail = (message) => {
  throw new Error(message);
};
function renderPure(context, selection, sources) {
  // Context must come from the future authorized caller, never developer choices.
  if (
    Object.keys(context).sort().join() !==
    "environment,moduleSha,sequence,teamId"
  )
    fail("Unexpected context fields");
  if (
    typeof context.teamId !== "string" ||
    !/^[A-Z][0-9]{3}$/.test(context.teamId) ||
    context.environment !== "dev" ||
    !Number.isInteger(context.sequence) ||
    context.sequence < 1 ||
    context.sequence > 99
  )
    fail("Invalid trusted context");
  if (
    typeof context.moduleSha !== "string" ||
    !/^[a-f0-9]{40}$/.test(context.moduleSha)
  )
    fail("A real immutable module commit SHA is required");
  if (Object.keys(selection).sort().join() !== "system,user")
    fail("Exactly System and User are required");
  const { catalogBytes, namingBytes, template } = sources;
  const catalog = YAML.parse(catalogBytes.toString());
  const c = catalog.eks;
  if (
    c.schema_version !== 1 ||
    c.configuration_model !== "system_user_profiles"
  )
    fail("Unsupported catalog");
  if (
    JSON.stringify(c.kubernetes.allowed_versions) !== '["1.36"]' ||
    JSON.stringify(c.cluster.allowed_regions) !== '["us-east-1"]'
  )
    fail("Review catalog changes before updating renderer");
  // This renderer is intentionally draft-only, even if someone supplies a new catalog.
  if (
    c.networking.conformity !== "pending" ||
    Object.keys(c.networking.approved_options).length
  )
    fail("Renderer requires the pending Networking draft");
  let total = 0;
  const profiles = {},
    counts = {};
  for (const role of ["system", "user"]) {
    const g = selection[role],
      policy = c.nodegroups[role];
    if (Object.keys(g).sort().join() !== "desired,maximum,minimum,size")
      fail("Only size and quantities are developer choices");
    if (!["S", "M"].includes(g.size) || !Object.hasOwn(policy.sizes, g.size))
      fail("Unauthorized profile");
    for (const n of [g.minimum, g.desired, g.maximum])
      if (!Number.isInteger(n) || n < policy.min_count || n > policy.max_count)
        fail("Quantity outside catalog");
    if (g.minimum > g.desired || g.desired > g.maximum)
      fail("Quantities must be ordered");
    total += g.maximum;
    profiles[role] = g.size;
    counts[role] = {
      minimum: g.minimum,
      desired: g.desired,
      maximum: g.maximum,
    };
  }
  if (total > c.nodegroups.limits.max_total_nodes)
    fail("Aggregate maximum exceeded");
  const instance = `eks-${String(context.sequence).padStart(2, "0")}`;
  const workspace = `workspaces/${context.teamId}/terraform/aws/${context.environment}/${instance}`;
  let main = template;
  const values = {
    WORKSPACE: workspace,
    TEAM: JSON.stringify(context.teamId),
    ENVIRONMENT: JSON.stringify(context.environment),
    INSTANCE: JSON.stringify(instance),
    PROFILES: JSON.stringify(profiles),
    COUNTS: JSON.stringify(counts),
    MODULE_SHA: context.moduleSha,
    SEQUENCE: String(context.sequence),
  };
  // JSON object member colons are valid HCL expression separators.
  for (const [k, v] of Object.entries(values))
    main = main.replaceAll(`@@${k}@@`, v);
  if (main.includes("@@")) fail("Unresolved template token");
  let backend = `bucket = "s3ue1p001dev01"\nregion = "us-east-1"\nkey = "states/${context.teamId}/aws/${context.environment}/${instance}/terraform.tfstate"\nencrypt = true\nuse_lockfile = true\n`;
  return {
    workspace,
    files: {
      "main.tf": main,
      "backend.hcl": backend,
      "catalog.snapshot.json": JSON.stringify(catalog, null, 2) + "\n",
      "naming.snapshot.json": namingBytes.toString(),
      "generation.json":
        JSON.stringify(
          {
            status: "DRAFT_BLOCKED",
            networking: "pending",
            moduleSha: context.moduleSha,
            catalogPath: "aws/dev/eks.yaml",
            catalogSha256: digest(catalogBytes),
            namingSha256: digest(namingBytes),
            context,
            selection,
          },
          null,
          2
        ) + "\n",
    },
  };
}
module.exports = { renderPure };
