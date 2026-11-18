{
  description = "ruby-jira-mcp — read-only Jira/Confluence MCP server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            ruby_4_0
            bundler
            sqlite
            pkg-config
            gnumake
            gcc
            libyaml
            openssl
            zlib
            git
          ];

          shellHook = ''
            export RUBY_GC_HEAP_GROWTH_FACTOR=1.1
            export RUBYOPT="--disable=did_you_mean,error_highlight,syntax_suggest"
            echo "ruby-jira-mcp dev shell: $(ruby -v)"
            echo "run: make install && make test"
          '';
        };
      });

      packages = forAllSystems ({ pkgs }: {
        default = pkgs.writeShellApplication {
          name = "jira-mcp-http";
          runtimeInputs = with pkgs; [ ruby_4_0 bundler sqlite ];
          text = ''
            root="''${JIRA_MCP_ROOT:-$PWD}"
            export BUNDLE_GEMFILE="$root/mcp/Gemfile"
            export BUNDLE_PATH="''${BUNDLE_PATH:-$root/mcp/vendor/bundle}"
            export RUBY_GC_HEAP_GROWTH_FACTOR="''${RUBY_GC_HEAP_GROWTH_FACTOR:-1.1}"
            export RUBYOPT="''${RUBYOPT:-} --disable=did_you_mean,error_highlight,syntax_suggest"
            cd "$root/mcp"
            exec bundle exec ruby bin/jira-mcp-http "$@"
          '';
        };
      });

      apps = forAllSystems ({ pkgs }: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.default}/bin/jira-mcp-http";
        };
      });
    };
}
