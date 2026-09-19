---
name: cpa-imagegen
description: Generate images through the user's configured CPA or CLIProxyAPI OpenAI-compatible /v1/images/generations endpoint. Use when the user requests CPA image generation, or image generation in their established CPA workflow even if Codex has no built-in image tool. Includes a Windows PowerShell helper that reuses local Codex configuration and credentials without printing secrets.
---

# CPA image generation

This user has chosen CPA image generation as a reusable workflow. When a user requests an image in this CPA setup, use this API path without re-asking whether to use CLI fallback. A request to inspect configuration alone does not authorize generating images. Tool-level network and filesystem approvals still apply.

## Verified behavior

On 2026-09-19, the configured CPA returned `gpt-image-2` in `GET /v1/models` and successfully generated an image through `POST /v1/images/generations` using `gpt-image-2`, `1536x864`, and `quality=high`. The generation took 38 seconds. These are observed settings, not a guarantee of future model availability.

The SDK initially failed with `httpcore.ConnectError: EOF occurred in violation of protocol` while using the machine's HTTP proxy. Adding **only the configured CPA hostname** to the current process's `NO_PROXY` fixed it. The helper uses that behavior and restores the environment afterward. Use `-UseSystemProxy` if the network requires the machine proxy. Do not disable TLS verification or change persistent proxy/Codex settings.

## Use

Read the installed `../.system/imagegen/SKILL.md` for prompt shaping, output inspection, and model constraints. This helper depends on that skill's unmodified `scripts/image_gen.py` and invokes it directly; it is not a separate SDK implementation.

1. Write the requested image prompt to a UTF-8 text file in the current project. Choose an unused output filename under `output/imagegen/`.
2. Use an existing Python environment with `openai`. The helper prefers the current project's `.venv/Scripts/python.exe`, then `python`; `-Python` selects a different interpreter. Install dependencies only when missing. Python 3.8.8 was verified with `openai==1.99.9` and `jiter==0.9.1`; newer Python environments may use a current SDK. Do not downgrade an existing environment unnecessarily.
3. Optionally run `-Probe` to list model IDs. A listed model is not proof that generation will succeed. Use `-DryRun` to validate the prompt, image parameters, and output path without reading credentials or sending a request.
4. Run the helper to generate, inspect the resulting image with `view_image`, and return the image inline plus its absolute saved path and prompt file. State that CPA API/CLI was used.

```powershell
$cpaSkillRoot = Join-Path $env:USERPROFILE '.codex/skills/cpa-imagegen'
# If CODEX_HOME is set, use its skills/cpa-imagegen folder instead.
& "$cpaSkillRoot/scripts/Invoke-CpaImage.ps1" -Probe
& "$cpaSkillRoot/scripts/Invoke-CpaImage.ps1" `
  -PromptFile 'output/imagegen/scene.prompt.txt' `
  -Out 'output/imagegen/scene.png' `
  -Model 'gpt-image-2' -Size '1536x864' -Quality high
```

The script reads the top-level `model_provider` and that provider's `base_url` from `$CODEX_HOME/config.toml` (otherwise `~/.codex/config.toml`). It accepts CPA/CLIProxyAPI-named providers only, so an unrelated configured service does not receive these credentials. It supports the ordinary quoted-string provider table layout used by this installation, not profile overrides, inline tables, or arbitrary TOML. If configuration uses one of those forms, inspect the effective configuration and adapt deliberately; do not guess a host or substitute a different provider.

If the provider names an `env_key`, the script uses only that environment variable. Otherwise it reads the static `OPENAI_API_KEY` field from the same Codex home's `auth.json`. It never prints or persists the key. It does not reuse ChatGPT OAuth tokens. Missing credentials require local configuration; never request that a secret be pasted into chat.

## Failure handling

- A sandbox/network rejection requires the normal tool escalation flow. Do not claim the endpoint is unsupported based on a sandbox error.
- Missing Python SDK: install into the selected environment, then retry. For the verified Python 3.8 environment: `python -m pip install "openai==1.99.9" "jiter==0.9.1"`.
- `401`/`403`: stop and report an authentication/access problem without exposing credential contents.
- `404` or unsupported model: report the actual endpoint/model response; do not silently switch host or model. Never silently switch to `gpt-image-1.5`.
- Timeout or uncertain completion: inspect output and available request status before another paid generation. Avoid automatic retry loops or duplicate images. The bundled SDK may itself retry transient errors.
- The helper never overwrites an existing image. Choose a new name for another version.
