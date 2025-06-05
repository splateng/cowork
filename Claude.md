# `cowork` one-file bash cli for isolated development sessions using devcontainers and full clones

IMPORTANT: All code you write and actions you take must not conflict with any of the project requirements listed in this doc. If you feel there is something you need to do that might conflict, you must ask for more information until you have 95% confidence it is correct. You should always make sure this project doc is up to date and has the most correct as of the current project status.

VERY IMPORTANT: Before changing code, stop and ask questions until you are **≥ 95% confident** you understand the task.

## Project Info for Cowork Isolated Session Manager

We do not want to support anthropic api keys, as that will interfere with out oauth login.

### File locations

- Host OS cowork directory for all config and shared data:
  - `~/.cowork/`
- Session directories (full clones):
  - `~/.cowork/sessions/{project}-{session-name}/`
- Shared auth achieved after a claude login:
  - `~/.cowork/auth/`
- `cowork` is the bin command we want to use. Folks can either copy it to their /usr/bin/ directly, or they can clone this repo and run a script that will copy the latest version of it over for them (overwriting it in /usr/bin/ ) while making it executable

### Configuration Options

Config file is called `.cowork.conf` and it should be in a `/.cowork/` directory.

Configuration will be read from the following locations:
At the user level
`~/.cowork/.cowork.conf`
And at the project level (which supersedes the user level configs if there are conflicts.)
`<project_root>/.cowork/.cowork.conf`

`<project_root>.cowork.conf` settings:

- `SESSIONS` : available sessions to connect to. This is populated by `cowork init`, and erased during `cowork clean` as part of session removal

## Core Requirements (non negotiable)

- Usage: `cowork <command> [options]`
- must be a single bash file to run that can create all the other files it will need. (this means we are creating dockerfiles, settings files, etc from the single bash script as well, not copying them or reading them from this repo. Most users will not need to clone this repo at all)
- uses full git clones to create complete isolation between feature branches so they can work in parallel
- each clone is worked on in its own devcontainer instance
- Code lives directly in session directories at ~/.cowork/sessions/{project}-{session}/
- Code persists on the host filesystem - survives container restarts, Docker daemon restarts, even reboots
- No syncing needed - code is directly in the cloned directories
- leverages devcontainers spec and the @devcontainers/cli for container management
- respects existing .devcontainer/devcontainer.json files in projects
- anthropic cli is installed in containers (either via existing devcontainer.json or our default)
- we share login credentials among all containers by logging in via a temporary devcontainer once during setup (or again later via the `cowork auth` command) and copying the credentials out of the temp container and to a central location on the host os at `~/.cowork/auth`. All session containers mount this directory.
- if any containers require new login, we run `cowork auth` and it will update the central credentials again. The worktree containers should either automatically re copy the credentials from the host os, or maybe they can have a live link as long as they have permissions. im not sure if that will work.
- can work locally or via ssh
- Project configuration - Saves session names to `<project_root>/.cowork/.cowork.conf` in your project
- Resumable sessions - Containers persist between connections
- Clean command structure - init, list, connect, sync, auth, etc.
- Since this is essentially a developer tool, the containers should copy the

## Cowork API

- `cowork auth`: boot a temporary devcontainer to login to anthropic and save the credentials to the host operating system's `~/.cowork/auth` directory.
- `cowork init <session_name1> <session_name2> ...`: Initialize development sessions for this project by creating full clones.
- `cowork list`: List all configured sessions and their status
- `cowork connect <session_name>`: Connect to a specific session's devcontainer
- `cowork status`: Show detailed status of all sessions
- `cowork stop`: Stop all running devcontainers
- `cowork clean`: Remove all containers and session directories
- `cowork help`: show the help message

Examples:

### Initialize with three sessions

`cowork init feature-backend feature-frontend bugfix-auth`

This example sets up three development sessions, each with their own full clone and devcontainer, ready with auth

### Connect to a session

`cowork connect feature-backend`

This example connects to the existing session in the `feature-backend` devcontainer

## CURRENT PROJECT STATUS - DEVCONTAINER MIGRATION COMPLETE

### What Changed
We successfully migrated from Docker + git worktrees to devcontainers + full clones approach. This provides:
- **Simpler implementation** - No complex Docker volume management or syncing
- **Better compatibility** - Works with existing devcontainer.json files
- **Standard tooling** - Uses official @devcontainers/cli
- **Complete isolation** - Each session has its own full clone

### Implementation Files
- `./cowork.sh` - Main implementation using devcontainers (COMPLETE)
- `./devcontainers-migration.md` - Explains the new approach and user workflow
- `./old_cowork.sh` - Previous Docker/worktree implementation (kept for reference)

### Key Features Implemented
1. **Authentication**: Temporary devcontainer for Claude login, credentials saved to `~/.cowork/auth/`
2. **Session Management**: Full clones in `~/.cowork/sessions/`
3. **Devcontainer Support**: 
   - Respects existing .devcontainer/devcontainer.json
   - Offers to create default config when missing
   - Shows users how to add auth mount for existing configs
4. **All Commands Working**: auth, init, list, connect, status, stop, clean, help

### Requirements
- Node.js and npm (for devcontainer CLI)
- Install devcontainer CLI: `npm install -g @devcontainers/cli`
- Docker Desktop or compatible Docker engine

### Next Steps
- Test with various real-world projects
- Consider automatic devcontainer.json modification for auth mounts
- Add more devcontainer features to default template
