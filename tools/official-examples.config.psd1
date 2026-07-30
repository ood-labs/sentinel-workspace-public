@{
    MinimumSentinelVersion = '0.5.49'
    LiveProofHostVersion = '0.5.51'
    CapabilityCommandCount = 152
    CapabilitySchemaHash = 'f87e5c1d5f3ae458'

    ExcludedProjects = @(
        'desert_totem',
        'fruit_atlas_scatter',
        'procedural_building_system',
        'streamdiff_collage',
        'topographic_hud'
    )

    ExclusiveSharedPaths = @(
        'modules/pl_blueprint_procedural_building',
        'modules/procedural_building_facade',
        'modules/procedural_building_finish',
        'modules/procedural_building_lighting',
        'modules/procedural_building_materials',
        'modules/procedural_building_render'
    )

    Projects = @{
        interaction_lab = @{
            ProjectFile = 'interaction_lab.sentinel'
            SharedModules = @('modules/data_scope', 'modules/signal_trails')
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
            SharedModules = @('modules/lfo', 'modules/resample')
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
            SharedModules = @('modules/audio_bands')
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
            SharedModules = @(
                'modules/scientific_seed_lab',
                'modules/scientific_organism_renderer',
                'modules/scientific_relief_chamber',
                'modules/scientific_topology_weaver',
                'modules/scientific_biotic_source',
                'modules/scientific_analysis_proxy',
                'modules/scientific_feature_temporalizer',
                'modules/scientific_synaptic_field',
                'modules/scientific_filament_memory',
                'modules/scientific_spectral_archive',
                'modules/scientific_signal_glyphs',
                'modules/scientific_performance_deck',
                'modules/scientific_final_grade'
            )
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
        showcase_gallery = @{
            ProjectFile = 'showcase_gallery.sentinel'
            Promote = $false
            SharedModules = @(
            )
            PassiveBuses = @(
                @{ PipelineId = 'signal'; ProjectDir = 'modules/signal'; Width = 480; Height = 270 }
                @{ PipelineId = 'strata_control'; ProjectDir = 'modules/strata_control'; Width = 480; Height = 270 }
                @{ PipelineId = 'dada_control'; ProjectDir = 'modules/dada_control'; Width = 480; Height = 270 }
            )
            MinimumSceneGroups = 7
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 7
            RequiresGroupsMux = $true
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('gallery-final-mux', 'scene-group-controls', 'scene-group-presets', 'object-picking')
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
        'projects/autopsia/*.png',
        'tools/audio_test/*.wav',
        'tools/audio_test/corpus/*.wav'
    )

    AllowedProjectDirectories = @('assets', 'cues', 'images', 'modules', 'proof')
    AllowedTopLevelFiles = @('README*', 'LICENSE*')
    GlobalSharedPaths = @('modules/_shared')
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
