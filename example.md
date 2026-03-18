---
title: "Markdown with Diagrams and Formulas"
author: "Example"
date: 2026-03-17
---

# Overview

This document demonstrates embedding **PlantUML**, **Graphviz**, **Mermaid**,
**Ditaa**, and **LaTeX formulas** in a Markdown document.

---

## PlantUML – Sequence Diagram

```plantuml
@startuml
actor User
participant "Frontend" as FE
participant "Backend" as BE
database "Database" as DB

User -> FE : Send request
FE -> BE : REST call
BE -> DB : Query
DB --> BE : Result
BE --> FE : JSON
FE --> User : Display
@enduml
```

## PlantUML – Class Diagram

```plantuml
@startuml
class Vehicle {
  +brand: String
  +year: int
  +drive(): void
}
class Car extends Vehicle {
  +doors: int
}
class Motorcycle extends Vehicle {
  +helmetRequired: boolean
}
@enduml
```

## Graphviz – Directed Graph

```graphviz
digraph G {
  rankdir=LR;
  node [shape=box, style=filled, fillcolor=lightyellow];

  Start -> "Step 1" -> "Step 2" -> End;
  Start -> "Step 3" -> End;

  Start [shape=circle, fillcolor=lightgreen];
  End [shape=doublecircle, fillcolor=lightcoral];
}
```

## Graphviz – State Machine

```graphviz
digraph fsm {
  rankdir=LR;
  node [shape=circle];

  S0 [label="Idle"];
  S1 [label="Running"];
  S2 [label="Error"];
  S3 [label="Done", shape=doublecircle];

  S0 -> S1 [label="start"];
  S1 -> S1 [label="tick"];
  S1 -> S2 [label="fail"];
  S1 -> S3 [label="finish"];
  S2 -> S0 [label="reset"];
}
```

## Mermaid – Flowchart

```mermaid
flowchart TD
    A[Start] --> B{Input valid?}
    B -- Yes --> C[Process]
    B -- No --> D[Error message]
    C --> E[Save result]
    D --> A
    E --> F[End]
```

## Mermaid – Gantt Chart

```mermaid
gantt
    title Project Plan
    dateFormat  YYYY-MM-DD
    section Design
    Concept           :done, d1, 2026-01-01, 14d
    Prototype         :active, d2, after d1, 21d
    section Development
    Backend           :e1, after d2, 30d
    Frontend          :e2, after d2, 25d
    section Testing
    Integration       :t1, after e1, 14d
```

## Ditaa – ASCII Art Diagram

```ditaa
    +--------+   +-------+    +-------+
    |        +---+ ditaa +----+       |
    | Text   |   +-------+    |Diagram|
    |Document|   |{io}   |    |       |
    |     {d}|   |       |    |       |
    +---+----+   +-------+    +-------+
        :                         ^
        |       Generation        |
        +-------------------------+
```

## TikZ – Vector Drawing

```tikz
\begin{tikzpicture}[node distance=2cm, auto, thick]
  \node[circle, draw, fill=green!20] (start) {Start};
  \node[rectangle, draw, fill=blue!10, right of=start] (process) {Process};
  \node[diamond, draw, fill=yellow!20, aspect=2, right of=process] (decision) {OK?};
  \node[circle, draw, fill=red!20, right of=decision] (end) {End};
  \node[rectangle, draw, fill=orange!10, below of=decision] (fix) {Fix};

  \draw[->] (start) -- (process);
  \draw[->] (process) -- (decision);
  \draw[->] (decision) -- node {yes} (end);
  \draw[->] (decision) -- node {no} (fix);
  \draw[->] (fix) -| (process);
\end{tikzpicture}
```

## LaTeX Formulas

### Inline

Euler's identity $e^{i\pi} + 1 = 0$ connects five fundamental constants.

### Block Formulas

The quadratic formula:

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

Solving quadratic equations (just for demonstrating complex formatting):

$$
  \begin{alignedat}{2}
    ax^2 + bx + c &= 0 &\quad|\; & - ax^2 \\
    bx + c &= - ax^2 &|\; & : a \\
    \frac{b}{a} x + \frac{c}{a} &= - x^2 &|\; & + \left(\frac{b}{2a}\right)^2 \\
    \frac{b}{a} x + \left(\frac{b}{2a}\right)^2 + \frac{c}{a} &= - x^2 + \left(\frac{b}{2a}\right)^2 &|\; & \\
    \left(x + \frac{b}{2a}\right)^2 &= -\frac{c}{a} + \left(\frac{b}{2a}\right)^2 &|\; & \sqrt{\cdot} \\
    x + \frac{b}{2a} &= \pm\sqrt{-\frac{c}{a} + \left(\frac{b}{2a}\right)^2} &|\; & -\frac{b}{2a} \\
    x &= -\frac{b}{2a} \pm\sqrt{-\frac{c}{a} + \left(\frac{b}{2a}\right)^2}
  \end{alignedat}
$$

The Gaussian integral:

$$
  \begin{aligned}
    x &= \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} \\
  \end{aligned}
$$

The Collatz conjecture considers the sequence:

$$a_{n+1} = \begin{cases} \frac{a_n}{2} & \text{if } a_n \text{ is even} \\ 3a_n + 1 & \text{if } a_n \text{ is odd} \end{cases}$$

## Summary

| Feature   | Syntax              | Rendering      |
|-----------|---------------------|----------------|
| PlantUML  | `` ```plantuml ``   | via Lua filter |
| Graphviz  | `` ```graphviz ``   | via Lua filter |
| Mermaid   | `` ```mermaid ``    | via Lua filter |
| Ditaa     | `` ```ditaa ``      | via Lua filter |
| TikZ      | `` ```tikz ``       | via Lua filter |
| LaTeX     | `$...$` / `$$...$$` | Pandoc native  |
