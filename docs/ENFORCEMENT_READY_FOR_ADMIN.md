Repository enforcement work is ready for admin review.

Actions required by repository/org admins:

- Disable GitHub Actions for this repository (see issue #2778).
- Block GitHub Releases in repository settings (see issue #2778).
- Require `Cloud Build` status checks in branch protection and add the `cloud-build` required check (see issue #2780).
- Review and merge PR: chore/remove-final-workflows-2 which contains housekeeping for enforcement readiness.

If you need the agent to remove archived workflow artifacts as part of this PR, grant permission or request the agent to proceed with file deletions.
