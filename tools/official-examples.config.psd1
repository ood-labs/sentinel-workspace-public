@{
    MinimumSentinelVersion = '0.5.49'
    LiveProofHostVersion = '0.5.51'
    CapabilityCommandCount = 152
    CapabilitySchemaHash = 'f87e5c1d5f3ae458'

    Projects = @{
        interaction_lab = @{
            ProjectFile = 'interaction_lab.sentinel'
            SharedModules = @()
            ProofRecords = @('docs/reviews/phase-6/interaction-lab.json')
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
            ProofRecords = @('docs/reviews/phase-6/living-room-sdf.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        face_collage = @{
            ProjectFile = 'face_collage.sentinel'
            SharedModules = @()
            ProofRecords = @('docs/reviews/phase-6/face-collage.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        strata = @{
            ProjectFile = 'strata.sentinel'
            SharedModules = @()
            ProofRecords = @('docs/reviews/phase-6/strata.json')
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
            ProofRecords = @('docs/reviews/phase-6/industrial-lattice.json')
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
            ProofRecords = @('docs/reviews/phase-6/camera-reference.json')
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
            ProofRecords = @('docs/reviews/phase-6/touchdesigner-new-project.json')
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
                'docs/reviews/phase-6/streamdiff-workflow-01.json',
                'docs/reviews/phase-6/streamdiff-workflow-02.json',
                'docs/reviews/phase-6/streamdiff-workflow-03.json',
                'docs/reviews/phase-6/streamdiff-workflow-04.json',
                'docs/reviews/phase-6/streamdiff-workflow-05.json',
                'docs/reviews/phase-6/streamdiff-workflow-06.json'
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
            ProofRecords = @('docs/reviews/phase-6/cloth-lab.json')
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
            ProofRecords = @('docs/reviews/phase-6/scientific-organism.json')
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 4
            RequireNodePreviews = $true
            Exemptions = @()
        }
        autopsia = @{
            ProjectFile = 'autopsia.sentinel'
            SharedModules = @()
            ProofRecords = @('docs/reviews/phase-6/autopsia.json')
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
            ProofRecords = @('docs/reviews/phase-6/streamdiff-canvas.json')
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
            Evidence = 'docs/reviews/phase-6/streamdiff-workflow-05.json'
        }
        @{
            Path = 'projects/touchdesigner_new_project/images/jellybeans.png'
            Source = 'User-selected replacement image'
            Purpose = 'Portable image input for the TouchDesigner starter reference'
            RedistributionStatus = 'cleared'
            Evidence = 'docs/reviews/phase-6/touchdesigner-new-project.json'
        }
    )
    GeneratedMediaPatterns = @(
        'projects/*/proof/*',
        'projects/autopsia/*.png'
    )

    WorkspaceManifest = @{
        Prefixes = @(
            '.agents/skills',
            '.claude/skills',
            'examples',
            'knowledge',
            'projects'
        )
        Files = @(
            '.gitignore',
            'AGENTS.md',
            'CLAUDE.md',
            'GEMINI.md',
            'LICENSE',
            'README.md',
            'tools/generate_laservibe_hud.py',
            'tools/module-ui.ps1',
            'tools/official-examples.config.psd1',
            'tools/test-official-examples.ps1',
            'tools/validate-official-examples.ps1',
            'tools/verify_motion_energy.py'
        )
    }

    AllowedProjectDirectories = @('assets', 'cues', 'images', 'modules', 'proof')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
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
        '.fx', '.hlsl', '.hlsli', '.json', '.md', '.ps1', '.sentinel',
        '.txt', '.yaml', '.yml'
    )
}
