// Draft file adapter. Formatting is a separate explicit operation; no AWS calls.
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { renderPure } = require("./render-eks-pure.cjs");
const ROOT = path.resolve(__dirname, "..");
const fail = (message) => {
  throw new Error(message);
};
function render(context, selection) {
  return renderPure(context, selection, {
    catalogBytes: fs.readFileSync(path.join(ROOT, "../eks.yaml")),
    template: fs.readFileSync(path.join(ROOT, "../main.tf"), "utf8"),
    namingBytes: fs.readFileSync(path.join(ROOT, "naming/aws.json")),
  });
}
function formatRendered(result) {
  const files = { ...result.files };
  for (const name of ["main.tf", "backend.hcl"]) {
    files[name] = execFileSync(
      process.env.TERRAFORM_BIN || "terraform",
      ["fmt", "-"],
      {
        input: files[name],
        encoding: "utf8",
      }
    );
  }
  return { ...result, files };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const format = args.at(-1) === "--format";
  if (format) args.pop();
  if (args.length !== 3)
    fail("Expected context, selection, output-root and optional --format");
  const [contextFile, selectionFile, destination] = args;
  if (!destination)
    fail(
      "Usage: node render-eks.cjs trusted-context.json selection.json output-root"
    );
  let result = render(
    JSON.parse(fs.readFileSync(contextFile)),
    JSON.parse(fs.readFileSync(selectionFile))
  );
  if (format) result = formatRendered(result);
  const out = path.join(path.resolve(destination), result.workspace);
  fs.mkdirSync(out, { recursive: true });
  if (fs.readdirSync(out).length)
    fail("Refusing to overwrite an existing workspace");
  for (const [file, data] of Object.entries(result.files))
    fs.writeFileSync(path.join(out, file), data, { flag: "wx" });
  console.log(out);
}
module.exports = { render, renderPure, formatRendered };
