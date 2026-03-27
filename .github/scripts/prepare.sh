#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/facebook/relay"
BRANCH="main"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_VERSION="20"

# Setup NVM
export NVM_DIR="${HOME}/.nvm"
if [ ! -f "${NVM_DIR}/nvm.sh" ]; then
  echo "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
source "${NVM_DIR}/nvm.sh"

# Install and use Node 20
nvm install ${NODE_VERSION}
nvm use ${NODE_VERSION}

echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"

# Clone (skip if already exists)
if [ ! -d "$REPO_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# Apply content fixes (from fixes.json if present)
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    python3 - "$FIXES_JSON" <<'PYEOF'
import sys
import os
import json

fixes_file = sys.argv[1]
with open(fixes_file) as f:
    config = json.load(f)

def fix_sidebar_items(items):
    """Recursively fix duplicate Relay Resolvers in sidebar items array."""
    result = []
    for item in items:
        if isinstance(item, dict):
            if (not item.get('type') and
                    'Relay Resolvers' in item and
                    isinstance(item['Relay Resolvers'], list) and
                    len(item['Relay Resolvers']) > 0 and
                    isinstance(item['Relay Resolvers'][0], str) and
                    item['Relay Resolvers'][0].startswith('api-reference/')):
                result.append({
                    'type': 'category',
                    'label': 'Relay Resolvers',
                    'key': 'APIReferenceRelayResolvers',
                    'items': item['Relay Resolvers'],
                })
                print(f"  Converted API Reference 'Relay Resolvers' shorthand to long-form with key.")
            elif not item.get('type') and isinstance(list(item.values())[0] if item else None, list):
                fixed_item = {}
                for k, v in item.items():
                    if isinstance(v, list):
                        fixed_item[k] = fix_sidebar_items(v)
                    else:
                        fixed_item[k] = v
                result.append(fixed_item)
            elif item.get('type') == 'category' and 'items' in item:
                fixed_item = dict(item)
                fixed_item['items'] = fix_sidebar_items(item['items'])
                result.append(fixed_item)
            else:
                result.append(item)
        else:
            result.append(item)
    return result

for file_path, ops in config.get('fixes', {}).items():
    if not os.path.exists(file_path):
        print(f'  skip (not found): {file_path}')
        continue
    for op in ops:
        if op['type'] == 'replace':
            with open(file_path, 'r') as f:
                content = f.read()
            if op['find'] in content:
                content = content.replace(op['find'], op.get('replace', ''))
                with open(file_path, 'w') as f:
                    f.write(content)
                print(f"  fixed: {file_path} - {op.get('comment', '')}")
            else:
                print(f"  WARNING: pattern not found in {file_path}")
        elif op['type'] == 'json_category_key':
            with open(file_path, 'r') as f:
                data = json.load(f)
            fixed_data = {}
            for sidebar_name, sidebar_items in data.items():
                if isinstance(sidebar_items, list):
                    fixed_data[sidebar_name] = fix_sidebar_items(sidebar_items)
                else:
                    fixed_data[sidebar_name] = sidebar_items
            with open(file_path, 'w') as f:
                json.dump(fixed_data, f, indent=2)
            print(f"  fixed: {file_path} - {op.get('comment', '')}")

for file_path, cfg in config.get('newFiles', {}).items():
    c = cfg if isinstance(cfg, str) else cfg.get('content', '')
    os.makedirs(os.path.dirname(file_path) if os.path.dirname(file_path) else '.', exist_ok=True)
    with open(file_path, 'w') as f:
        f.write(c)
    print(f"  created: {file_path}")

print('[INFO] Content fixes applied.')
PYEOF
fi

cd website

# Enable corepack and install yarn
corepack enable

# Install dependencies
yarn install

echo "[DONE] Repository is ready for docusaurus commands."
