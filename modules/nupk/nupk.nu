#!/usr/bin/env nu
use std/log

const GH_API = "https://api.github.com"
const OHMYNU = $nu.home-path  | path join .ohmynu
const PREFIX = $nu.home-path  | path join .local
const BIN_DIR = $PREFIX | path join bin
const DOWNLOAD_DIR = $OHMYNU | path join cache gh-downloads

def try-filter [
    predicate: closure,
] {
    let items = $in
    let length = $items | length
    let filtered = $items | where $predicate
    let filtered_length = $filtered | length

    if $filtered_length > 0 and $filtered_length < $length {
        return $filtered
    } else {
        return $items
    }
}

def shasum [
    digest: string
] {
    let file = $in
    if ($digest | str starts-with "sha256:") {
        (open $file | hash sha256) == ($digest | str substring 7..)
    } else if ($digest | str starts-with "md5:") {
        (open $file | hash md5) == ($digest | str substring 4..)
    } else {
        false
    }
}

def detect-target [] {
    return {
        "os": $nu.os-info.name
        "arch": $nu.os-info.arch
    }
}

def match-target [
    name: closure,
] {

    let items = $in | each {|it| { name: (do $name $it | str downcase), item: $it } }

    let target = detect-target
    let target_os = $target.os
    let target_arch = $target.arch


    let items = $items | where { |it| not ($it.name | str contains "sha256") }

    let items = $items | try-filter { |it| ($it.name | str contains $target_os) }
    let items = $items | try-filter { |it| ($it.name | str contains $target_arch) }

    let items = $items | try-filter { |it| ($it.name | str contains "musl") }

    let items = $items | each { |it| $it.item }
    return $items
}

def pkg [
    name: string
] {
    use alias.nu alias
    let name = if $name in $alias {
        $alias | get $name
    } else {
        $name
    }
    let s = $env.FILE_PWD | path join repo $"($name).nu"
    if not ($s | path exists) {
        print $"($name) not found"
        exit 1
    }
    let info = nu -n $s | from nuon
    return $info
}

def release [
    --version(-v): string = "latest"
    name: string
] {
    let pkg = pkg $name
    let repo = if $pkg != null {
        $"($pkg.owner)/($pkg.name)"
    } else {
        $name
    }
    let url = $"($GH_API)/repos/($repo)/releases/($version)"
    let data = http get $url
    return $data
}

def main [] {
    let x = {|x: string|
        print $"xxx ($x) xx"
    }

    do $x "a"
    do $x "b"
    print "GH helper"
}

def "main info" [name: string] {
    release $name | to nuon
}

def "main install" [
    name: string,
    --yes(-y),
    --version(-v): string = "latest"
    --dest(-d): string
    --prefix(-p): string
] {
    let bin_dir = if $prefix != null {
        $prefix | path join bin
    } else {
        $BIN_DIR
    }
    let prefix = if $prefix != null {
        $PREFIX
    } else {
        $BIN_DIR
    }
    let bin_dir = if $dest != null {
        $dest
    } else {
        $BIN_DIR
    }
    let target = detect-target

    log debug $"OS: ($target.os)"
    log debug $"Arch: ($target.arch)"

    let repo = pkg $name
    if $repo == null {
        print $"($name) not found"
        return
    }

    let bin_name = if $repo.commands? != null and ($repo.commands | length) > 0 {
        $repo.commands | get 0
    } else {
        $repo.name
    }
    let release = release -v $version $name
    let version = $release | get name | str trim -l -c v

    let is_latest = do {
        let bin_path = $bin_dir | path join $bin_name
        ($bin_path | path exists) and (^($bin_path) --version | str contains $version)
    }

    if $is_latest {
        print $"($name) is already at the latest version: ($version)"
        return
    }

    let assets = $release | get assets | match-target { |it| $it.name }
    if ($assets | length) == 0 {
        print $"No asset found for target: ($target)"
        return
    }
    let asset = match ($assets | length) {
        0 => {
            print "No asset found for target: ($target)"
            exit 1
        },
        1 => {
            $assets | first
        }
        _ => {
            print $"Multiple assets found for target: ($target), select one:"
            let idx = $assets | each { |it| $it.name } | input list --index
            let asset = $assets | get $idx
            print $"Selected asset: ($asset.name)"
            $asset
        }
    }

    let browser_download_url = $asset.browser_download_url
    let file_name = $asset.name
    let file_size = $asset.size
    let file_digest = $asset.digest?

    print $"name: ($name)"
    print $"version: ($version)"
    print $"size: ($asset.size)"
    print $"digest: ($file_digest)"
    print $"url: ($browser_download_url)"
    print $"release date: ($release.published_at)"

    if not $yes {
        print "Do you want to continue? "
        let confirm = ["no/N", "yes/Y"] | input list --index
        if $confirm == 0 {
            print "exit"
            exit 1
        }
    }

    try {
        let work_dir = $DOWNLOAD_DIR | path join $repo.name $release.name
        let dist_dir = $work_dir | path join "dist"

        if ($dist_dir | path exists) {
            rm -rf $dist_dir
        }
        mkdir $dist_dir

        let file_path = $work_dir | path join $file_name
        if ($file_path | path exists) and $file_digest != null and ($file_path | shasum $file_digest) {
            print $"File already exists and matches the digest: ($file_name) to ($work_dir)"
        } else {
            print $"Downloading: ($file_name) to ($work_dir)"
            curl -o $file_path -L ($browser_download_url)
            print $"Downloaded: ($file_name) to ($work_dir)"
        }
        print $"Extracting: ($file_name) to ($dist_dir)"
        let content_type = $asset | get content_type
        log debug $"Content Type: ($content_type)"
        match $content_type {
            "application/zip" => {
                unzip -q $file_path -d $dist_dir
            },
            "application/x-tar" => {
                tar -xvf $file_path -C $dist_dir
            },
            "application/gzip" | "application/x-gtar" => {
                tar -xzf $"($file_path)" -C $dist_dir
            }
            else => {
                print $"Unsupported content type: ($content_type)"
                exit 1
            }
        }

        print $"Extracted: ($file_name) to ($work_dir)"

        let entries = ls $dist_dir
        let dist_dir = if ($entries | length) == 1 and ($entries | first | get type) == "dir" {
            $dist_dir | path join ($entries | first | get name)
        } else {
            $dist_dir
        }

        mkdir $bin_dir

        if $repo.commands? != null {
            for file in $repo.commands {
                let src = $dist_dir | path join $file
                let dst = $bin_dir | path join $file
                if not ($src | path exists ) {
                    print $"Error: Command not found in distribution directory. ($src)"
                    exit 1
                }
                mv $src $dst
                chmod +x $dst
                print $"Installed: ($file) to ($bin_dir)"
            }
        } else {
            let src = $dist_dir | path join $bin_name
            let dst = $bin_dir | path join $bin_name
            if not ($src | path exists ) {
                print $"Error: Command not found in distribution directory. ($src)"
                exit 1
            }
            mv $src $dst
            chmod +x $dst
            print $"Installed: ($bin_name) to ($BIN_DIR)"
        }
    } catch { |err| 
        print $"Error: ($err)"
    }

    print "Cleaning up..."
    # rm -rf $work_dir
    print "Done."
}

def "main test" [] {
    let n = "lazygit"
    let s = pkg $n
    print $s
}