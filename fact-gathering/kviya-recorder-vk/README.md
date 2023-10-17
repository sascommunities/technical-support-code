# kviya-recorder - A Viya 4 realtime fact gathering tool

## Overview
While monitoring or debugging Viya 4 environments, we usually need to execute several 'kubectl' commands to check information from different objects. There are also scenarios where the information changes over time and it is required to 'watch' or keep executing different commands to capture information at the moment or location where somethins has failed or changed.

For SAS Tech Support, it gets even more challenging as customer environments are usually not reachable and handy 'kubectl' commands are not available.

This tool makes these tasks faster and easier by collecting "snapshots" from different k8s objects and organizing all information in a customized way that makes sense for Viya environments.

A kviya-recorder generated "playback file" can be read by SAS Technical Support using the internal tool called kviya.