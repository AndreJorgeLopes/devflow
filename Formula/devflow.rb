class Devflow < Formula
  desc "AI dev environment orchestrator — integrates Hindsight, Agent Deck, Worktrunk, Code Review, and Langfuse"
  homepage "https://github.com/AndreJorgeLopes/devflow"
  url "https://github.com/AndreJorgeLopes/devflow/releases/download/v0.24.0/devflow-0.24.0.tar.gz"
  version "0.24.0"
  license "MIT"
  sha256 "9bc383254f46aa287d46c928db15e5e5c88be4340ce0ec6343a02ef8e9d1ee09"

  depends_on "git"
  depends_on "tmux"

  def install
    # Core directories into libexec (private install root)
    libexec.install "lib"
    libexec.install "templates"
    libexec.install "skills"
    libexec.install "config"
    libexec.install "docker"

    # Install the main binary into libexec, then create a wrapper
    libexec.install "bin/devflow"
    (libexec/"bin/devflow").chmod 0755

    # Wrapper script that sets DEVFLOW_ROOT so devflow can find its resources
    (bin/"devflow").write <<~BASH
      #!/usr/bin/env bash
      export DEVFLOW_ROOT="#{libexec}"
      exec "#{libexec}/bin/devflow" "$@"
    BASH
    (bin/"devflow").chmod 0755
  end

  def caveats
    <<~EOS
      devflow is installed. To get started:
        devflow help

      Docker is required for some features. Install it with:
        brew install --cask docker

      Optional tools:
        brew install agent-deck worktrunk

      Optional CLI for clean web-page fetching in /devflow:review-document
      (and the personal defuddle skill if installed):
        npm install -g defuddle
      Without defuddle, web URLs fall back to WebFetch — works fine, just
      noisier output.
    EOS
  end

  test do
    assert_match "devflow #{version}", shell_output("#{bin}/devflow version 2>&1", 0)
  end
end
