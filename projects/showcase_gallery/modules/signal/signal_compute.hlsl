// Topographic operations signal resolver.
// Manual, autonomous, and Conductor sources all publish through one visible bus.

struct SigData {
    float pulse; float sweep; float beat; float slow;
    float terrain; float density; float blue_gain; float accent_gain;
    float nodes_gain; float labels_gain; float palette; float energy;
    float authority; float cue_mode; float master_mix; float phase;
    float marker; float pad0; float pad1; float pad2;
};

RWStructuredBuffer<SigData> OutputBuffer : register(u0);
static const float TAU = 6.28318530718;

void cueTargets(int cue, out float outTerrain, out float outDensity, out float outBlue,
                out float outAccent, out float outNodes, out float outLabels,
                out float outPalette, out float outMaster)
{
    if (cue == 1) { // Threat
        outTerrain = 1.0; outDensity = 96.0; outBlue = 0.45; outAccent = 1.65;
        outNodes = 1.45; outLabels = 0.72; outPalette = 1.0; outMaster = 1.18;
    } else if (cue == 2) { // Night vision
        outTerrain = 3.0; outDensity = 54.0; outBlue = 1.10; outAccent = 0.38;
        outNodes = 0.95; outLabels = 1.15; outPalette = 2.0; outMaster = 0.96;
    } else if (cue == 3) { // Minimal
        outTerrain = 0.0; outDensity = 28.0; outBlue = 0.55; outAccent = 0.20;
        outNodes = 0.70; outLabels = 0.45; outPalette = 3.0; outMaster = 0.72;
    } else if (cue == 4) { // Performance
        outTerrain = 2.0; outDensity = 44.0; outBlue = 0.72; outAccent = 0.82;
        outNodes = 0.82; outLabels = 0.58; outPalette = 0.0; outMaster = 0.82;
    } else { // Survey
        outTerrain = 2.0; outDensity = 68.0; outBlue = 0.95; outAccent = 1.05;
        outNodes = 1.00; outLabels = 0.92; outPalette = 0.0; outMaster = 1.00;
    }
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    SigData previous = OutputBuffer[0];
    bool initialized = abs(previous.marker - 76031.0) < 0.5;
    int source = clamp(authority, 0, 2);
    int cue = clamp(cue_mode, 0, 4);

    float autoPulse = 0.5 + 0.5 * sin(_Time * pulse_rate * TAU);
    float autoSweep = frac(_Time * sweep_rate);
    float autoBeat = pow(saturate(0.5 + 0.5 * sin(_Time * beat_rate * TAU)), max(beat_sharp, 0.1));
    float autoSlow = 0.5 + 0.5 * sin(_Time * 0.05 * TAU);

    float activePhase = source == 0 ? manual_sweep : (source == 1 ? autoSweep : frac(conductor_phase));
    float activeEnergy = source == 0 ? manual_energy :
                         (source == 1 ? saturate(autoPulse * 0.62 + autoBeat * 0.38) : saturate(conductor_energy));
    float activePulse = source == 0 ? manual_energy : (source == 1 ? autoPulse : saturate(0.35 + conductor_energy * 0.65));
    float activeBeat = source == 0 ? manual_energy : (source == 1 ? autoBeat : saturate(conductor_energy));
    float activeSlow = source == 0 ? manual_sweep : (source == 1 ? autoSlow : frac(conductor_phase));

    float targetTerrain = (float)terrain;
    float targetDensity = (float)node_density;
    float targetBlue = layer_blue;
    float targetAccent = layer_accent;
    float targetNodes = layer_nodes;
    float targetLabels = layer_labels;
    float targetPalette = (float)palette;
    float targetMaster = master_mix;

    if (source == 2) {
        cueTargets(cue, targetTerrain, targetDensity, targetBlue, targetAccent,
                   targetNodes, targetLabels, targetPalette, targetMaster);
        targetAccent *= lerp(0.82, 1.18, activeEnergy);
        targetNodes *= lerp(0.78, 1.20, activeEnergy);
    } else if (source == 1) {
        targetDensity = clamp(targetDensity + (autoSlow - 0.5) * 16.0, 12.0, 112.0);
        targetAccent *= lerp(0.88, 1.12, autoBeat);
        targetNodes *= lerp(0.86, 1.14, autoPulse);
    }

    SigData s = previous;
    float blend = initialized ? (1.0 - exp(-max(_DeltaTime, 1.0 / 240.0) * 8.0)) : 1.0;
    s.pulse = lerp(initialized ? previous.pulse : activePulse, activePulse, blend);
    s.sweep = lerp(initialized ? previous.sweep : activePhase, activePhase, blend);
    s.beat = lerp(initialized ? previous.beat : activeBeat, activeBeat, blend);
    s.slow = lerp(initialized ? previous.slow : activeSlow, activeSlow, blend);
    s.terrain = targetTerrain;
    s.density = lerp(initialized ? previous.density : targetDensity, targetDensity, blend);
    s.blue_gain = lerp(initialized ? previous.blue_gain : targetBlue, targetBlue, blend);
    s.accent_gain = lerp(initialized ? previous.accent_gain : targetAccent, targetAccent, blend);
    s.nodes_gain = lerp(initialized ? previous.nodes_gain : targetNodes, targetNodes, blend);
    s.labels_gain = lerp(initialized ? previous.labels_gain : targetLabels, targetLabels, blend);
    s.palette = targetPalette;
    s.energy = lerp(initialized ? previous.energy : activeEnergy, activeEnergy, blend);
    s.authority = (float)source;
    s.cue_mode = (float)cue;
    s.master_mix = lerp(initialized ? previous.master_mix : targetMaster, targetMaster, blend);
    s.phase = activePhase;
    s.marker = 76031.0;
    s.pad0 = s.pad1 = s.pad2 = 0.0;
    OutputBuffer[0] = s;
}
