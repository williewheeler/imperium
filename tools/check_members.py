#!/usr/bin/env python3
"""Static check that GDScript's parser does not do: every `sim.X`, `sim.part.Y` and `game.X` named in the code
exists on the class it must be (Simulation, its parts, Main). Run from the project root: python3 tools/check_members.py"""
import re, sys, os, glob

def members(path):
    s = open(path).read()
    names = set(re.findall(r'^(?:static )?func (\w+)', s, re.M))
    names |= set(re.findall(r'^(?:static )?var (\w+)', s, re.M))
    names |= set(re.findall(r'^const (\w+)', s, re.M))
    names |= set(re.findall(r'^signal (\w+)', s, re.M))
    names |= set(re.findall(r'^enum (\w+)', s, re.M))
    return names

SIM_PARTS = {  # Simulation member -> the class it holds
    'movement': 'movement', 'economy': 'economy', 'production': 'production', 'eras': 'eras', 'vision': 'vision',
    'wildlife': 'wildlife', 'behavior': 'unit_behavior', 'combat': 'combat', 'orders': 'orders', 'commands': 'commands',
    'placement': 'placement', 'roads': 'roads', 'victory': 'victory', 'setup': 'world_setup',
}
sim_members = members('src/sim/simulation.gd')
part_members = {k: members('src/sim/systems/%s.gd' % v) for k, v in SIM_PARTS.items()}
state_members = members('src/sim/state/game_state.gd')
main_members = members('src/app/main.gd')
MAIN_PARTS = {'person': members('src/ui/controls/person.gd'), 'rig': members('src/ui/controls/camera_rig.gd')}
NODE_BUILTIN = set('get_tree get_viewport get_viewport_rect add_child position queue_redraw get_window get_global_mouse_position visible name'.split())

bad = 0
files = [f for f in glob.glob('src/**/*.gd', recursive=True) + glob.glob('tools/*.gd') + glob.glob('tests/*.gd')]
for f in files:
    for n, line in enumerate(open(f).read().split('\n'), 1):
        code = line.split('#')[0] if '"' not in line.split('#')[0] else line  # crude: keep lines with strings whole
        for m in re.finditer(r'(?<![\w])(?:[\w.]*\.)?sim\.(\w+)(?:\.(\w+))?', code):
            a, b = m.group(1), m.group(2)
            if a not in sim_members:
                print('%s:%d: Simulation has no %r' % (f, n, a)); bad += 1
            elif b and a == 'state' and b not in state_members:
                print('%s:%d: GameState has no %r' % (f, n, b)); bad += 1
            elif b and a in part_members and b not in part_members[a]:
                print('%s:%d: %s has no %r' % (f, n, a, b)); bad += 1
        for m in re.finditer(r'(?<![\w.])_?game\.(\w+)(?:\.(\w+))?', code):
            a, b = m.group(1), m.group(2)
            if a not in main_members and a not in NODE_BUILTIN and a != 'sim':
                print('%s:%d: Main has no %r' % (f, n, a)); bad += 1
            elif b and a in MAIN_PARTS and b not in MAIN_PARTS[a]:
                print('%s:%d: %s has no %r' % (f, n, a, b)); bad += 1
# the AIs read the game only through their PlayerView and act only through their HeadlessClient
for f in glob.glob('src/ai/*.gd'):
    for n, line in enumerate(open(f).read().split('\n'), 1):
        code = line.split('#')[0]
        for word in [r'\bsim\b', r'\bSimulation\b', r'\bGameState\b', r'\bCombat\.']:
            if re.search(word, code):
                print('%s:%d: the AIs may not touch the simulation (%s); use ai.view and ai.client' % (f, n, code.strip()[:60])); bad += 1
                break
# the UI (the screens, the views, the controls) knows the game only through the player's view
for f in glob.glob('src/ui/**/*.gd', recursive=True):
    for n, line in enumerate(open(f).read().split('\n'), 1):
        code = line.split('#')[0]
        for word in [r'\.sim\b', r'\bSimulation\b', r'\bGameState\b', r'\.state\.(units|buildings|map|stocks|fogs)']:
            if re.search(word, code):
                print('%s:%d: the UI may not touch the simulation (%s); use game.view and game.client' % (f, n, code.strip()[:60])); bad += 1
                break
# a client reads nothing of the simulation but its own frames: the only touches are attaching to the queues (and asking for a view now)
ALLOWED_CLIENT = ('_sim.open_view(', '_sim.publish_view(', '_sim.put_command(', 'sim.answered.connect(', 'Simulation.TICK')
for f in glob.glob('src/client/*.gd'):
    for n, line in enumerate(open(f).read().split('\n'), 1):
        code = line.split('#')[0]
        if re.search(r'\b_?sim\.|\bGameState\b|\.state\.', code) and not any(a in code for a in ALLOWED_CLIENT):
            print('%s:%d: a client may not read the simulation (%s); it has its frames' % (f, n, code.strip()[:60])); bad += 1
print('check_members: %d problems' % bad)
sys.exit(1 if bad else 0)
