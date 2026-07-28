class Devflow < Formula
  desc "AI dev environment orchestrator — integrates Hindsight, Agent Deck, Worktrunk, Code Review, and Langfuse"
  homepage "https://github.com/AndreJorgeLopes/devflow"
  url "https://github.com/AndreJorgeLopes/devflow/releases/download/v0.27.0/devflow-0.27.0.tar.gz"
  version "0.27.0"
  license "MIT"
  sha256 "53c4902edd190a51acc182d40fb9dd800dd55845471dcf771fe4da3df5ac79c0"

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
