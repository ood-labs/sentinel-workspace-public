@{
    MinimumSentinelVersion = '0.5.52'
    LiveProofHostVersion = '0.5.52'
    CapabilityCommandCount = 152
    CapabilitySchemaHash = 'f87e5c1d5f3ae458'

    Projects = @{
        interaction_lab = @{
            ProjectFile = 'interaction_lab.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/interaction-lab.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            MinimumGroupPresets = 0
            MinimumNodePresets = 2
            Exemptions = @('approved-ungrouped-instrument', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        living_room_sdf = @{
            ProjectFile = 'living_room_sdf.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/living-room-sdf.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        matik_plate = @{
            ProjectFile = 'matik_plate.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/matik-plate.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 6
            Exemptions = @('scene-group-presets', 'technical-workflow-output')
        }
        prism_reliquary = @{
            ProjectFile = 'prism_reliquary.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/prism-reliquary.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 7
            Exemptions = @('scene-group-presets', 'technical-workflow-output')
        }
        face_collage = @{
            ProjectFile = 'face_collage.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/face-collage.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        strata = @{
            ProjectFile = 'strata.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/strata.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 1
            Exemptions = @('scene-group-controls')
        }
        industrial_lattice = @{
            ProjectFile = 'industrial_lattice.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/industrial-lattice.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            MinimumGroupPresets = 0
            MinimumNodePresets = 2
            Exemptions = @('approved-compact-study', 'object-picking', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        camera_reference = @{
            ProjectFile = 'camera_reference.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/camera-reference.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('focused-reference', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        touchdesigner_new_project = @{
            ProjectFile = 'touchdesigner_new_project.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/touchdesigner-new-project.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('starter-reference', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        streamdiff_workflows = @{
            ProjectFiles = @(
                '01_2d_feedback_zoom.sentinel',
                '02_depth_parallax_zoom.sentinel',
                '03_backrooms_flythrough.sentinel',
                '04_direct_variant_mux.sentinel',
                '05_video_depth_control.sentinel',
                '06_procedural_warp_map.sentinel'
            )
            SharedModules = @()
            ProofRecords = @(
                '.release/reviews/phase-6/streamdiff-workflow-01.json',
                '.release/reviews/phase-6/streamdiff-workflow-02.json',
                '.release/reviews/phase-6/streamdiff-workflow-03.json',
                '.release/reviews/phase-6/streamdiff-workflow-04.json',
                '.release/reviews/phase-6/streamdiff-workflow-05.json',
                '.release/reviews/phase-6/streamdiff-workflow-06.json'
            )
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('project-collection', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        cloth_lab = @{
            ProjectFile = 'cloth_lab.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/cloth-lab.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 1
            Exemptions = @('scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        scientific_organism = @{
            ProjectFile = 'scientific_organism.sentinel'
            ProofRecords = @('.release/reviews/phase-6/scientific-organism.json')
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 4
            RequireNodePreviews = $true
            Exemptions = @()
        }
        soft_vitrine = @{
            ProjectFile = 'soft_vitrine.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/soft-vitrine.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 6
            Exemptions = @('scene-group-presets', 'technical-workflow-output')
        }
        autopsia = @{
            ProjectFile = 'autopsia.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/autopsia.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            MinimumGroupPresets = 0
            MinimumNodePresets = 2
            RequireNodePreviews = $true
            Exemptions = @('scene-group-presets')
        }
        streamdiff_canvas = @{
            ProjectFile = 'streamdiff_canvas.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-6/streamdiff-canvas.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            MinimumGroupPresets = 0
            MinimumNodePresets = 2
            RequireNodePreviews = $true
            Exemptions = @('scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
    }

    AssetLedger = @(
        @{
            Path = 'projects/streamdiff_workflows/assets/dancer_vert.mp4'
            Source = 'User-selected clip'
            Purpose = 'Video input for the approved depth-control and matte-composite workflow'
            RedistributionStatus = 'cleared'
            Evidence = '.release/reviews/phase-6/streamdiff-workflow-05.json'
        }
        @{
            Path = 'projects/touchdesigner_new_project/images/jellybeans.png'
            Source = 'User-selected replacement image'
            Purpose = 'Portable image input for the TouchDesigner starter reference'
            RedistributionStatus = 'cleared'
            Evidence = '.release/reviews/phase-6/touchdesigner-new-project.json'
        }
    )
    GeneratedMediaPatterns = @()

    SupportedTopLevelTools = @(
        'audit-public-release.ps1',
        'module-ui.ps1',
        'official-examples.config.psd1',
        'plan-public-release.ps1',
        'promote-public.ps1',
        'test-official-examples.ps1',
        'update-workspace-manifest.ps1',
        'validate-official-examples.ps1'
    )

    AllowedTopLevelDirectories = @(
        '.agents',
        '.claude',
        '.release',
        'examples',
        'knowledge',
        'projects',
        'tools'
    )

    AllowedRepositoryFiles = @(
        '.gitignore',
        '.mcp.json',
        '.sentinel-workspace-manifest.json',
        '.sentinel-workspace-version',
        'AGENTS.md',
        'CLAUDE.md',
        'GEMINI.md',
        'LICENSE',
        'README.md'
    )

    RetiredReferences = @(
        'generate_laservibe_hud.py',
        'interaction-lab-guards.py',
        'interaction-lab-handson.py',
        'invoke-sentinel-mcp.ps1',
        'repair-scene-group-presets.ps1',
        'sentinel_bridge.py',
        'sentinel_mcp_call.py',
        'spline_probe.py',
        'verify_motion_energy.py',
        'tracking_ripple.sentinel',
        'timeline_hud',
        'choreo_cascade'
    )

    Scientifica = @{
        FileName = 'scientifica_ascii.hlsli'
        Sha256 = 'fda36f3bad9f8d0090f824b53bc7818249845b00ad3f347337d5e4b6f8616f56'
        LicenseFileName = 'SCIENTIFICA_LICENSE.txt'
    }

    WorkspaceManifest = @{
        Prefixes = @(
            '.agents/skills',
            '.claude/skills',
            'examples',
            'knowledge',
            'projects',
            'tools/templates/module-ui'
        )
        Files = @(
            '.gitignore',
            '.mcp.json',
            '.sentinel-workspace-version',
            'AGENTS.md',
            'CLAUDE.md',
            'GEMINI.md',
            'LICENSE',
            'README.md',
            'tools/module-ui.ps1'
        )
    }

    AllowedProjectDirectories = @('assets', 'cues', 'images', 'modules', 'tools')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
    RequiredProjectReadmeHeading = '## Component map'
    GlobalSharedPaths = @()
    ForbiddenDirectoryNames = @(
        '.cache', '.shadercache', 'captures', 'checkpoint', 'checkpoints',
        'recovery', 'shader_cache', 'shadercache'
    )
    ForbiddenFileNames = @(
        '.env', '.env.*', 'DEBRIEF.md', 'provider*.json', 'vision.json',
        '*.cso', '*.log', '*.pdb', '*.tmp'
    )
    TextExtensions = @(
        '.fx', '.hlsl', '.hlsli', '.json', '.md', '.ps1', '.py', '.sentinel',
        '.txt', '.yaml', '.yml'
    )
}
