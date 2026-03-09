#!/usr/bin/env python3
"""
Simple helper: updates terraform files to pin runner image to a new tag and opens a PR.
Usage: python3 terraform_pin_updater.py --image ghcr.io/org/runner:tag
"""
import argparse, os, subprocess, tempfile, re, sys, requests, json

parser = argparse.ArgumentParser()
parser.add_argument('--image', required=True)
args = parser.parse_args()

IMAGE = args.image
REPO = os.environ.get('GITHUB_REPOSITORY')
TOKEN = os.environ.get('GITHUB_TOKEN')
if not REPO or not TOKEN:
    print('GITHUB_REPOSITORY and GITHUB_TOKEN required in env')
    sys.exit(2)

branch = f'auto/image-pin-{int(os.time.time())}' if hasattr(os, 'time') else f'auto/image-pin-{int(subprocess.check_output(["date","+%s"]).strip())}'
branch = branch.replace(' ','-')

# create branch
subprocess.check_call(['git', 'config', 'user.email', 'auto@github-actions'])
subprocess.check_call(['git', 'config', 'user.name', 'gha-bot'])
subprocess.check_call(['git', 'checkout', '-b', branch])

# naive replace: look for ghcr.io/... lines in terraform files
pattern = re.compile(r'ghcr.io/[^:\"\s]+/[^:\"\s]+(:[0-9A-Za-z_.-]+)?')
changed = False
for root, dirs, files in os.walk('.'):
    for f in files:
        if f.endswith('.tf') or f.endswith('.yaml') or f.endswith('.yml'):
            path = os.path.join(root,f)
            with open(path,'r') as fh:
                txt = fh.read()
            new = pattern.sub(IMAGE, txt)
            if new != txt:
                with open(path,'w') as fh:
                    fh.write(new)
                subprocess.check_call(['git', 'add', path])
                changed = True

if not changed:
    print('No image pins found to update')
    sys.exit(0)

subprocess.check_call(['git', 'commit', '-m', f'chore: pin image {IMAGE}'])
subprocess.check_call(['git', 'push', '-u', 'origin', branch])

# create PR via GitHub API
owner, repo = REPO.split('/')
url = f'https://api.github.com/repos/{owner}/{repo}/pulls'
headers = {'Authorization': f'token {TOKEN}','Accept':'application/vnd.github.v3+json'}
body = {'title': f'Pin image {IMAGE}', 'head': branch, 'base': 'main', 'body': f'Automated image pin for {IMAGE}'}
resp = requests.post(url, headers=headers, json=body)
if resp.status_code >=200 and resp.status_code < 300:
    print('PR created:', resp.json().get('html_url'))
else:
    print('Failed creating PR', resp.status_code, resp.text)
    sys.exit(2)
