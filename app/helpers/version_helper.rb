# frozen_string_literal: true

# Helpers for displaying the current code version in the views.
module VersionHelper

  # The current release version for HEAD
  VERSION = `git describe --tags --long`

  # The current release version for HEAD
  #
  # Returns String
  def version
    VERSION
  end

end
