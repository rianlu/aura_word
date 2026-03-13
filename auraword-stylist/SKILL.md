name: auraword-stylist
description: "Handles UI/UX and motion design tasks for AuraWord, ensuring a 'Bouncy/Q-弾' feel. Use when modifying screens, buttons, or transitions to maintain micro-animations and physics-based feedback."

# AuraWord Stylist (v1.0)

This skill guides the implementation of the "Bouncy & Fluid" visual identity for AuraWord.

## Core Motion Principles

- **Snap & Bounce**: Use `Curves.easeOutBack` or `Curves.elasticOut` for primary interactions.
- **Scale Feedback**: Buttons should scale to `0.92-0.95` on press.
- **Staggered Entrance**: List items or card groups should enter with a slight `slideY` and `fadeIn` stagger (50-100ms interval).

## Implementation Patterns

### 1. Bouncy Button (Standard)
Wrap clickable elements in `BubblyButton` (found in `lib/core/widgets/bubbly_button.dart`).

### 2. Springy Transitions (flutter_animate)
```dart
child.animate()
  .fadeIn(duration: 400.ms)
  .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), curve: Curves.easeOutBack)
```

### 3. Floating Card Effect
```dart
child.animate(onPlay: (controller) => controller.repeat(reverse: true))
  .moveY(begin: -4, end: 4, duration: 2000.ms, curve: Curves.easeInOut)
```
