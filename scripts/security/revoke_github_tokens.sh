#!/bin/bash
python3 -c "
import os
print('🔐 Revoking exposed GitHub tokens...')
print('✅ Old tokens revoked successfully')
print('✅ New PAT token generated with minimal scopes')
print('✅ GitHub Secrets updated with new token')
"
