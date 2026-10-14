@{
    MinimumSentinelVersion = '0.5.61'
    LiveProofHostVersion = '0.5.61'
    CapabilityCommandCount = 158
    CapabilitySchemaHash = '8f361a936de555d1'

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
        # Replaces living_room_sdf as the room example; its blueprints live on as tools/templates/blueprints/living_room.
        breathing_room = @{
            ProjectFile = 'breathing_room.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/release-0.6.8/breathing_room.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 7
            Exemptions = @()
        }
        formicary = @{
            ProjectFile = 'formicary.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-8/formicary.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 30
            Exemptions = @('approved-ungrouped-instrument', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        kuka_cell = @{
            ProjectFile = 'kuka_cell.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-8/kuka-cell.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 10
            Exemptions = @('scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        spectral_bench = @{
            ProjectFile = 'spectral_bench.sentinel'
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-8/spectral-bench.json')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 5
            Exemptions = @('scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
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
        # Committed directly (scripts/, presets/ and docs/ are outside AllowedProjectDirectories),
        # so promotion skips it; the validator, audit and workspace manifest still cover it.
        phage_stage = @{
            ProjectFile = 'phage_stage.sentinel'
            Promote = $false
            SharedModules = @()
            # Reviewed in phase 10 as stagerig_phage; renamed phage_stage for 0.6.1.
            ProofRecords = @('.release/reviews/phase-10/stagerig_phage.json', '.release/reviews/release-0.6.8/phage_stage.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 5
            Exemptions = @('approved-ungrouped-instrument', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        # The club-scale stage on PHAGE's show system, committed directly like PHAGE (scripts/, presets/, docs/ and rigs/).
        simple_stage = @{
            ProjectFile = 'simple_stage.sentinel'
            Promote = $false
            SharedModules = @()
            ProofRecords = @('.release/reviews/release-0.6.8/simple_stage.json')
            MinimumSceneGroups = 0
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 5
            Exemptions = @('approved-ungrouped-instrument', 'scene-group-controls', 'scene-group-presets', 'technical-workflow-output')
        }
        # Committed directly (scripts/ and docs/ are outside AllowedProjectDirectories), like PHAGE.
        laser_mapping_lab = @{
            ProjectFile = 'laser_mapping_lab.sentinel'
            Promote = $false
            SharedModules = @()
            ProofRecords = @('.release/reviews/phase-10/laser_mapping_lab.json')
            MinimumSceneGroups = 3
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 3
            RequireNodePreviews = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 6
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
    )
    # Generated by the workspace's own tools: the IBM Plex type atlas (tools/il_type.py, OFL notice beside every copy),
    # the stage examples' GDTF thumbnails (their GDTF writers) and README images (captures of the projects), and
    # Formicary's synthesised kick.
    GeneratedMediaPatterns = @(
        'projects/*/modules/_shared/type/il_type.png',
        'tools/templates/*/*/modules/_shared/type/il_type.png',
        'projects/*/assets/gdtf/thumbnails/*.png',
        'projects/simple_stage/docs/*.png',
        'projects/formicary/audio/kick_120bpm.wav'
    )

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
        'knowledge',
        'projects',
        'tools'
    )

    AllowedRepositoryFiles = @(
        '.gitattributes',
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
        'choreo_cascade',
        'klangrig',
        'stagerig_phage'
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
            'knowledge',
            'projects',
            'tools/templates/module-includes',
            'tools/templates/dmx',
            'tools/templates/fixtures',
            'tools/templates/blueprints',
            'tools/templates/module-ui',
            'tools/templates/scripts'
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

    AllowedProjectDirectories = @('assets', 'cues', 'docs', 'images', 'modules', 'presets', 'scripts', 'tools')
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
        '.fx', '.hlsl', '.hlsli', '.json', '.luau', '.md', '.ps1', '.py', '.sentinel',
        '.txt', '.yaml', '.yml'
    )
}
