# Utility methods
def git_commit(message, with_rubocop: true)
  if with_rubocop
    Bundler.with_clean_env do
      run "bundle exec rubocop -a"
    end
  end
  git add: "."
  git commit: "-n -m '#{message}'"
end

def bundle_install
  run "bundle install --jobs=4 --without="
end

# Main processing
after_bundle do
  run "spring stop"

  ## initial commit
  git_commit "rails new", with_rubocop: false

  ## install gems
  proc_install_rubocop
  proc_install_rspec
  proc_install_simplecov
  proc_install_pry
  proc_install_hamlit

  ## uninstall gems
  proc_uninstall_jbuilder if yes?("Would you like to uninstall jbuilder? (y/n): ")

  ## i18n
  proc_localize if yes?("Would you like to localize to Japan? (y/n): ")

  ## railtie
  proc_setup_railties

  ## initializers
  proc_setup_initializers
end

# Sub Processings
def proc_install_rubocop # rubocop:disable Metrics/MethodLength
  gem_group :development do
    gem "rubocop", require: false
    gem "rubocop-packaging", require: false if Rails.version >= "6.1.0"
    gem "rubocop-performance", require: false
    gem "rubocop-rails", require: false
  end
  bundle_install
  git_commit "Install rubocop", with_rubocop: false

  # fetch rails/rails/.rubocop
  rails_rubocop_file = ".rubocop-#{Rails.version.gsub(".", "-")}.yml"
  run "curl -L https://raw.githubusercontent.com/rails/rails/v#{Rails.version}/.rubocop.yml > #{rails_rubocop_file}"
  # replace old cop
  gsub_file(rails_rubocop_file, "Layout/Tab", "Layout/IndentationStyle")

  create_file ".rubocop.yml", <<~RUBOCOP_YML
    inherit_from:
      - #{rails_rubocop_file}

    AllCops:
      Exclude:
        - 'bin/**/*'
        - 'config/**/*'
        - 'db/**/*'
        - 'node_modules/**/*'
        - 'tmp/**/*'
        - 'vendor/**/*'

    Style/FrozenStringLiteralComment:
      Enabled: false
  RUBOCOP_YML
  run "bundle exec rubocop -a"
  git_commit "rubocop -a"
end

def proc_install_rspec
  gem_group :test do
    gem "rspec-rails", group: :development
  end
  bundle_install
  git_commit "Install rspec-rails"
  generate "rspec:install"
  run "rm -rf test"
  git_commit "rails g rspec:install"
end

def proc_install_simplecov
  gem_group :test do
    gem "simplecov"
  end
  bundle_install
  run "echo coverage >> .gitignore"
  git_commit "Install simplecov"
end

def proc_install_pry
  gem_group :development do
    gem "pry-byebug"
  end
  bundle_install
  git_commit "Install pry-byebug"
end

def proc_install_hamlit
  gem "hamlit-rails"
  gem "html2haml"
  bundle_install
  git_commit "Install hamlit-rails"
  run "bundle exec rake hamlit:erb2haml"
  git_commit "rake hamlit:erb2haml"
end

def proc_uninstall_jbuilder
  comment_lines "Gemfile", /^gem "jbuilder"/
  bundle_install
  git_commit "Uninstall jbuilder"
end

def proc_localize
  application do
    <<~CONF
      config.time_zone = "Tokyo"
      config.i18n.default_locale = :ja
    CONF
  end
  run "curl -o config/locales/ja.yml -L https://raw.githubusercontent.com/svenfuchs/rails-i18n/master/rails/locale/ja.yml"
  git_commit "Localize to Japan"
end

def proc_setup_railties # rubocop:disable Metrics/MethodLength
  # https://github.com/rails/rails/blob/master/railties/lib/rails/all.rb
  default_railties = %w[
    active_record/railtie
    active_storage/engine
    action_controller/railtie
    action_view/railtie
    action_mailer/railtie
    active_job/railtie
    action_cable/engine
    action_mailbox/engine
    action_text/engine
    rails/test_unit/railtie
    sprockets/railtie
  ]

  my_railties = default_railties.dup

  ### active_storage/engine
  my_railties.delete("active_storage/engine") if yes?("Would you like to disable active_storage? (y/n): ")

  ### action_text/engine
  my_railties.delete("action_text/engine") if yes?("Would you like to disable action_text? (y/n): ")

  diff_railties = default_railties - my_railties
  return if diff_railties.empty?

  comment_lines "config/application.rb", 'require "rails/all"'
  inject_into_file "config/application.rb", after: '# require "rails/all"' do
    my_railties.map { |railtie| "require \"#{railtie}\"" }.join("\n")
  end
  git_commit "Disable #{diff_railties.join(', ')}"
end

def proc_setup_initializers
  return if Rails.version >= "6.0.4"

  create_file "config/initializers/active_support_backports.rb", <<~IRB_SETTINGS
    # Fix IRB deprecation warning on tab-completion.
    #
    # Backports the fix for https://github.com/rails/rails/issues/37097
    # from https://github.com/rails/rails/pull/37100
    #
    # Backports proposed fix for https://github.com/rails/rails/pull/37468
    # from https://github.com/rails/rails/pull/37468
    module ActiveSupportBackports

      warn "[DEPRECATED] #{self} should no longer be needed. Please remove!" if Rails.version >= '6.0.4'

      def self.prepended(base)
        base.class_eval do
          delegate :hash, :instance_methods, :respond_to?, to: :target
        end
      end
    end

    module ActiveSupport
      class Deprecation
        class DeprecatedConstantProxy
          prepend ActiveSupportBackports
        end
      end
    end
  IRB_SETTINGS
  git_commit "Add backport of irb compleation"
end
