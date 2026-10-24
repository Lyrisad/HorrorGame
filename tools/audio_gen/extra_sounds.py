"""
Ne régénère que certains sons (sans toucher aux autres fichiers).

Usage :  python extra_sounds.py <dossier_sortie>
"""
import generate_sounds as g


def main():
    g.write("wiper", g.wiper(), 0.5)
    g.write("wiper_cycle_loop", g.wiper_cycle(), 0.55)
    g.write("gasmask_breath_loop", g.gasmask_breath_loop(), 0.7)
    for i in range(3):
        g.write(f"ringtone_{i}", g.ringtone(i), 0.6)
    g.write("phone_tap", g.phone_tap(), 0.4)
    g.write("message_sent", g.message_sent(), 0.5)
    g.write("ringback", g.ringback(), 0.4)
    g.write("glass_break", g.glass_break(), 0.85)
    g.write("jumpscare", g.jumpscare(), 0.95)
    g.write("tap_running_loop", g.tap_running_loop(), 0.5)
    for i in range(3):
        g.write(f"creature_growl_{i}", g.creature_growl(i), 0.85)
    g.write("steam_hiss_loop", g.steam_hiss_loop(), 0.6)
    g.write("wind_gust", g.wind_gust(), 0.75)
    g.write("owl_hoot", g.owl_hoot(), 0.6)
    for i in range(2):
        g.write(f"flashlight_tap_{i}", g.flashlight_tap(i), 0.5)
        g.write(f"dying_cough_{i}", g.dying_cough(i), 0.75)
    for i in range(3):
        g.write(f"dying_murmur_{i}", g.dying_murmur(i), 0.55)
    g.write("dying_breath_loop", g.dying_breath_loop(), 0.6)
    g.write("death_rattle", g.death_rattle(), 0.6)
    print("OK")


if __name__ == "__main__":
    main()
