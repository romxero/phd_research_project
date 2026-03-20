# PhD Project Name Pending
## Date: 2026-03-20
## Author: Randall White
## Email: randall.white@gmail.com
## Version: 1.0.0
### Info

This is a project looking at the pronatalist community on reddit. 

Downloading data requires git LFS support. 


### Software Requirements
Currently this all works on either linux or mac osx (more work is needed here).

Testing some of the workloads on H100, B200, B300, M1 and M4 SoCs. 

git lfs support is utilized since the data sets can exceed 50Mb.



### Time line
```mermaid
gantt
    title Computational PhD dissertation (Dec 2025 → May 2027 defense)
    dateFormat  YYYY-MM-DD
    axisFormat  %b %Y

    section Setup & foundations
    Orientation, tooling, compute & reproducibility baseline :crit, setup, 2025-12-01, 2026-02-28
    Core methods / algorithms survey                       :methods, 2025-12-15, 2026-04-30
    Related work & positioning (running doc)             :related, 2026-01-01, 2026-08-31

    section Proposal
    Problem formulation & milestones                     :prob, 2026-02-01, 2026-06-30
    Preliminary experiments / baselines                  :prelim, 2026-03-01, 2026-08-31
    Proposal writing                                     :propwrite, 2026-05-01, 2026-11-15
    Committee feedback & revisions                       :proprev, 2026-09-01, 2026-12-31
    Proposal defense / qualifying                        :milestone, propdef, 2027-01-15, 0d

    section Core computational research
    Implementation (codebase, pipelines, tests)          :impl, 2026-06-01, 2027-03-31
    Main experiments & benchmarks                        :exps, 2026-09-01, 2027-04-30
    Ablations, scaling, failure analysis                 :ablate, 2027-01-01, 2027-05-10
    Reproducibility package (configs, seeds, artifacts)  :repro, 2027-02-01, 2027-05-15

    section Writing & completion
    Paper-style drafts → dissertation chapters           :papers, 2026-11-01, 2027-05-20
    Full draft to committee                              :fulldraft, 2027-03-01, 2027-04-25
    Committee review & revision cycle                    :rev, 2027-04-01, 2027-05-12
    Final formatting & submission prep                   :final, 2027-05-01, 2027-05-14
    Dissertation defense (May 2027)                      :milestone, defense, 2027-05-15, 0d
    Final deposit / corrections                          :milestone, deposit, 2027-05-29, 0d
```



-RC 


