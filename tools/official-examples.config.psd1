@{
    MinimumSentinelVersion = '0.5.35'

    Projects = @{
        interaction_lab = @{
            ProjectFile = 'interaction_lab.sentinel'
            SharedModules = @()
            MinimumSceneGroups = 3
            RequiresGroupOutput = $false
            MinimumGroupPresets = 1
            MinimumNodePresets = 2
            Exemptions = @('single-final-output')
        }
        living_room_sdf = @{
            ProjectFile = 'living_room_sdf.sentinel'
            SharedModules = @()
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
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        fruit_atlas_scatter = @{
            ProjectFile = 'fruit_atlas_scatter.sentinel'
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        topographic_hud = @{
            ProjectFile = 'topographic_hud.sentinel'
            SharedModules = @()
            PassiveBuses = @(
                @{ PipelineId = 'signal'; ProjectDir = 'modules/signal'; Width = 480; Height = 270 }
            )
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        strata = @{
            ProjectFile = 'strata.sentinel'
            SharedModules = @()
            PassiveBuses = @(
                @{ PipelineId = 'strata_control'; ProjectDir = 'modules/strata_control'; Width = 480; Height = 270 }
            )
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        desert_totem = @{
            ProjectFile = 'desert_totem.sentinel'
            SharedModules = @()
            PassiveBuses = @(
                @{ PipelineId = 'dada_control'; ProjectDir = 'modules/dada_control'; Width = 480; Height = 270 }
            )
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            ExpectedGroupOutputs = 0
            RequireNodePreviews = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        industrial_lattice = @{
            ProjectFile = 'industrial_lattice.sentinel'
            SharedModules = @('modules/industrial_mono_post', 'modules/steel_lattice')
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @('object-picking')
        }
        procedural_building_system = @{
            ProjectFile = 'procedural_building_system.sentinel'
            SharedModules = @(
                'modules/pl_blueprint_procedural_building',
                'modules/procedural_building_facade',
                'modules/procedural_building_materials',
                'modules/procedural_building_lighting',
                'modules/procedural_building_render'
            )
            MinimumSceneGroups = 1
            RequiresGroupOutput = $false
            MinimumGroupPresets = 0
            MinimumNodePresets = 0
            Exemptions = @('scene-group-presets', 'technical-workflow-output')
        }
        showcase_gallery = @{
            ProjectFile = 'showcase_gallery.sentinel'
            Promote = $false
            SharedModules = @()
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

    AllowedProjectDirectories = @('assets', 'cues', 'modules', 'proof')
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
