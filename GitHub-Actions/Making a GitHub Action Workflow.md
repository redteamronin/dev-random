
Brief situation:
- Some GitHub projects don't provide releases.

Brief goal:
- Leverage GitHub actions to build a release for me then publish it to my repo.

Hurdles:
- Feed in a list of external GitHub repositories
- Setup a Windows environment to do the building
- Loop over repositories
- Automatically take the repository name and make it a variable
- Clone the repository
- Look in the repository for outdated `TargetFrameworkVersion` in `.csproj` files
- Update it to v4.8
- Use nuget to restore
- Some repositories use FodyWeaver to assist in building a single exe file
- If `FodyWeaver.xml` is not found, use ILMerge to create a single exe (merging in DLLs)
- Save `artifiacts` to GitHub as published releases

Repos tested:
- https://github.com/tomcarver16/ADSearch
	- Uses Fody Weaver for single executable file
- https://github.com/GhostPack/Rubeus
	- TargetFrameworkVersion of v4.0
- https://github.com/rasta-mouse/ThreatCheck
	- Normal build in Visual Studio has depend DLLs separate

Final GitHub Action Workflow yml:
```
name: Multi-Repo Builder

on:
  workflow_dispatch:
    inputs:
      repositories:
        description: 'Comma-separated list of repository URLs'
        required: true
        default: 'https://github.com/rasta-mouse/ThreatCheck,https://github.com/GhostPack/Rubeus,https://github.com/tomcarver16/ADSearch'

jobs:
  monitor-and-build:
    runs-on: windows-latest
    permissions:
      contents: write

    steps:
      - name: Set up MSBuild
        uses: microsoft/setup-msbuild@v1

      - name: Install NuGet
        uses: nuget/setup-nuget@v1

      - name: Loop Over Repositories
        shell: pwsh
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $repoUrls = "${{ github.event.inputs.repositories }}" -split ','
          $artifactPaths = @()

		  # --- Foreach Repository ---
          foreach ($repoUrl in $repoUrls) {
            # Extract repository name
            $repoName = $repoUrl.Split('/')[-1]
            Write-Host "Processing repository: $repoName"

            # --- Clone repository ---
            git clone $repoUrl external-repo\$repoName
            $repoPath = "external-repo\$repoName"
            $outputDir = "$repoPath\$repoName\bin\Release"

            # --- Update Target Framework ---
            $csprojFile = Get-ChildItem -Path $repoPath -Recurse -Filter *.csproj | Select-Object -First 1
            if ($csprojFile) {
                [xml]$csprojXml = Get-Content $csprojFile.FullName
                $namespaceMgr = New-Object System.Xml.XmlNamespaceManager($csprojXml.NameTable)
                $namespaceMgr.AddNamespace("ns", $csprojXml.Project.NamespaceURI)

                # --- Locate TargetFrameworkVersion ---
                $frameworkNodes = $csprojXml.SelectNodes("//ns:TargetFrameworkVersion", $namespaceMgr)
                if ($frameworkNodes.Count -gt 0) {
                    foreach ($node in $frameworkNodes) {
                        $currentFramework = $node.InnerText.Trim()
                        Write-Host "Found TargetFrameworkVersion: $currentFramework"
                        if ($currentFramework -eq "v4.0" -or $currentFramework -lt "v4.7.2") {
                            Write-Host "Updating TargetFrameworkVersion to v4.8"
                            $node.InnerText = "v4.8"
                        } else {
                            Write-Host "No update required. Current version: $currentFramework"
                        }
                    }
                    $csprojXml.Save($csprojFile.FullName)
                    Write-Host "TargetFrameworkVersion updated successfully."
                } else {
                    Write-Host "TargetFrameworkVersion node not found for $repoName."
                }
            } else {
                Write-Host "No csproj file found for $repoName. Skipping framework update."
            }

            # --- Restore and Build Solution ---
            nuget restore $repoPath\$repoName.sln
            msbuild $repoPath\$repoName.sln /p:Configuration=Release
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Build failed for $repoName. Skipping further steps."
                continue
            }

            # --- Detect FodyWeavers.xml ---
            $fodyConfig = Get-ChildItem -Path $repoPath -Recurse -Filter "FodyWeavers.xml" | Select-Object -First 1
            if ($fodyConfig) {
              Write-Host "Detected Fody in $repoName. No ILMerge required."
              $artifactPath = "$outputDir\$repoName.exe"
              & $artifactPath --help
            } else {
              Write-Host "No Fody detected in $repoName. Using ILMerge."
              nuget install ilmerge -Version 3.0.29 -OutputDirectory ilmerge
              $ilmergePath = (Resolve-Path ./ilmerge/ilmerge.3.0.29/tools/net452/ILMerge.exe).Path
              $dependencies = Get-ChildItem -Path "$outputDir" -Filter *.dll | ForEach-Object { $_.FullName }
              &$ilmergePath /out:"$outputDir\$repoName-merged.exe" "$outputDir\$repoName.exe" $dependencies
              $artifactPath = "$outputDir\$repoName-merged.exe"
              if (-Not (Test-Path $artifactPath)) {
                throw "Merged executable not created for $repoName"
              }
              & $artifactPath --help
            }

            # --- Save artifact path ---
            $artifactPaths += $artifactPath
          }

          # --- Export all artifacts for upload ---
          echo "ARTIFACT_PATHS=$($artifactPaths -join ',')" >> $env:GITHUB_ENV

      - name: Upload Executables to GitHub Release
        uses: ncipollo/release-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          tag: weekly-release
          name: "Weekly Release for Built Repositories"
          artifacts: ${{ env.ARTIFACT_PATHS }}
          allowUpdates: true
```