@{
    MinimumSentinelVersion = '0.5.33'

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
            RequiresGroupOutput = $true
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
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        strata = @{
            ProjectFile = 'strata.sentinel'
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
            MinimumGroupPresets = 3
            MinimumNodePresets = 2
            Exemptions = @()
        }
        desert_totem = @{
            ProjectFile = 'desert_totem.sentinel'
            SharedModules = @()
            MinimumSceneGroups = 1
            RequiresGroupOutput = $true
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
        showcase_gallery = @{
            ProjectFile = 'showcase_gallery.sentinel'
            SharedModules = @()
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
    AllowedTopLevelFiles = @('*.sentinel', 'README*', 'LICENSE*')
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
