# Git Deployment Sequence

Follow this step-by-step terminal guide to safely initialize, commit, and push the Offline Mesh Communication project to your designated repository.

### Prerequisites
Ensure you are in the root directory of your Flutter project.

```bash
cd /Users/mr.rocky/Desktop/rocksv2/offline_mesh_app
```

### 1. Initialize Git Repository
If the repository has not been initialized yet:
```bash
git init
```

### 2. Add Files to Staging
Ensure the `.gitignore` file is in place first, then add all safe files:
```bash
git add .
```

### 3. Commit the Project
Create the initial commit with a professional message:
```bash
git commit -m "feat: complete offline mesh architecture with zero-persistence cryptography"
```

### 4. Set Main Branch
Ensure your default branch is set to `main` (the modern standard):
```bash
git branch -M main
```

### 5. Link the Remote Repository
Link your local repository to the specific GitHub target:
```bash
git remote add origin https://github.com/pritampriya222-maker/rocksv2.git
```
*(If you get an error that the remote already exists, you can update it using: `git remote set-url origin https://github.com/pritampriya222-maker/rocksv2.git`)*

### 6. Push to GitHub
Push your committed code to the remote repository. 
```bash
git push -u origin main
```
*(You may be prompted for your GitHub credentials or Personal Access Token depending on your Git configuration).*
