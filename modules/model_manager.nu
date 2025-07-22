#!/usr/bin/env nu

def ms_hub [] {
  $"($env.HOME)/.cache/modelscope/hub/models"
}

def hf_hub [] {
  $"($env.HOME)/.cache/huggingface/hub"
}


def hf_path [name] {
  cd $"($env.HOME)/.cache/huggingface/hub"
  let modle_dirs = ls -f | where ( $it.name == $name or ($it.name | str ends-with $name))
  if ($modle_dirs | is-not-empty ) {
    let $modle_dir = $modle_dirs | first | get name
    let main = open $"($modle_dir)/refs/main"
    $"($modle_dir)/snapshots/($main)"
  } else {
    null
  }
}

def ms_path [name] {
  cd $"($env.HOME)/.cache/modelscope/hub/models"
  let modle_dirs = ls -f ./*/* | where ( $it.name == $name or ($it.name | str ends-with $name))
  mut modle_dir = null
  if ($modle_dirs | is-not-empty ) {
    $modle_dirs | first | get name
  } else {
    null
  }
}

def list_models [] {
  cd (ms_hub)
  let m1 = ls ./*/* | each { |it| $it.name | path basename  }
  cd (hf_hub)
  let m2 = ls | where type == dir and name != tmp | get name | each { |it| $it | split row  "--" | last }

  let models = $m1 | append $m2 | uniq
  return $models
}

def main [
    name: string
] {
    let path = ms_path $name
    let path = if $path == null {
        hf_path $name
    } else {
        $path
    }
    if ($path == null) {
      print $"Model not found: ($name)"
      exit 1
    }
    print $path
}



export def "main loc" [
    name: string@list_models
] {
    let path = ms_path $name
    let path = if $path == null {
        hf_path $name
    } else {
        $path
    }
    if ($path == null) {
      print $"Model not found: ($name)"
      exit 1
    }
    print $path
}

export def "main list" [] {
  let models = list_models
  for $model in $models {
    print $"($model)"
  }
}