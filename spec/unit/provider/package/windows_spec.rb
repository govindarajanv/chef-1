#
# Author:: Bryan McLellan <btm@loftninjas.org>
# Copyright:: Copyright (c) 2014 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'spec_helper'
require 'chef/provider/package/windows/exe'
require 'chef/provider/package/windows/msi'

describe Chef::Provider::Package::Windows, :windows_only do
  before(:each) do
    allow(Chef::Util::PathHelper).to receive(:windows?).and_return(true)
    allow(Chef::FileCache).to receive(:create_cache_path).with("package/").and_return(cache_path)
  end

  let(:node) { double('Chef::Node') }
  let(:events) { double('Chef::Events').as_null_object }  # mock all the methods
  let(:run_context) { double('Chef::RunContext', :node => node, :events => events) }
  let(:resource_source) { 'calculator.msi' }
  let(:resource_name) { 'calculator' }
  let(:new_resource) do
    new_resource = Chef::Resource::WindowsPackage.new(resource_name)
    new_resource.source(resource_source)
    new_resource
  end
  let(:provider) { Chef::Provider::Package::Windows.new(new_resource, run_context) }
  let(:cache_path) { 'c:\\cache\\' }

  before(:each) do
    allow(::File).to receive(:exist?).with(provider.new_resource.source).and_return(true)
  end

  describe "load_current_resource" do
    shared_examples "a local file" do
      before(:each) do
        allow(Chef::Util::PathHelper).to receive(:validate_path)
        allow(provider).to receive(:package_provider).and_return(double('package_provider',
          :installed_version => "1.0", :package_version => "2.0"))
      end

      it "creates a current resource with the name of the new resource" do
        provider.load_current_resource
        expect(provider.current_resource).to be_a(Chef::Resource::WindowsPackage)
        expect(provider.current_resource.name).to eql(resource_name)
      end

      it "sets the current version if the package is installed" do
        provider.load_current_resource
        expect(provider.current_resource.version).to eql("1.0")
      end

      it "sets the version to be installed" do
        provider.load_current_resource
        expect(provider.new_resource.version).to eql("2.0")
      end
    end

    context "when the source is a uri" do
      let(:resource_source) { 'https://foo.bar/calculator.msi' }

      context "when the source has not been downloaded" do
        before(:each) do
          allow(provider).to receive(:downloadable_file_missing?).and_return(true)
        end
        it "sets the current version to unknown" do
          provider.load_current_resource
          expect(provider.current_resource.version).to eql("unknown")
        end
      end

      context "when the source has been downloaded" do
        before(:each) do
          allow(provider).to receive(:downloadable_file_missing?).and_return(false)
        end
        it_behaves_like "a local file"
      end
    end

    context "when source is a local file" do
      it_behaves_like "a local file"
    end
  end

  describe "package_provider" do
    shared_examples "a local file" do

      it "checks that the source path is valid" do
        expect(Chef::Util::PathHelper).to receive(:validate_path)
        provider.package_provider
      end

      it "sets the package provider to MSI if the the installer type is :msi" do
        allow(provider).to receive(:installer_type).and_return(:msi)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::MSI)
      end

      it "sets the package provider to Exe if the the installer type is :inno" do
        allow(provider).to receive(:installer_type).and_return(:inno)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::Exe)
      end

      it "sets the package provider to Exe if the the installer type is :nsis" do
        allow(provider).to receive(:installer_type).and_return(:nsis)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::Exe)
      end

      it "sets the package provider to Exe if the the installer type is :wise" do
        allow(provider).to receive(:installer_type).and_return(:wise)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::Exe)
      end

      it "sets the package provider to Exe if the the installer type is :installshield" do
        allow(provider).to receive(:installer_type).and_return(:installshield)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::Exe)
      end

      it "defaults to exe if the installer_type is unknown" do
        allow(provider).to receive(:installer_type).and_return(nil)
        expect(provider.package_provider).to be_a(Chef::Provider::Package::Windows::Exe)
      end
    end

    context "when the source is a uri" do
      let(:resource_source) { 'https://foo.bar/calculator.msi' }

      context "when the source has not been downloaded" do
        before(:each) do
          allow(provider).to receive(:should_download?).and_return(true)
        end

        it "should create a package provider with source pointing at the local file" do
          expect(Chef::Provider::Package::Windows::MSI).to receive(:new) do |r|
            expect(r.source).to eq("#{cache_path}#{::File.basename(resource_source)}")
          end
          provider.package_provider
        end

        it_behaves_like "a local file"
      end

      context "when the source has been downloaded" do
        before(:each) do
          allow(provider).to receive(:should_download?).and_return(false)
        end
        it_behaves_like "a local file"
      end
    end

    context "when source is a local file" do
      it_behaves_like "a local file"
    end
  end

  describe "installer_type" do
    let(:resource_source) { "microsoft_installer.exe" }

    context "there is no source" do
      let(:uninstall_hash) do
        [{
          'DisplayVersion' => 'outdated',
          'UninstallString' => "blah blah"
        }]
      end
      let(:uninstall_key) { "blah" }
      let(:uninstall_entry) do
        entries = []
        uninstall_hash.each do |entry|
          entries.push(Chef::Provider::Package::Windows::RegistryUninstallEntry.new('hive', uninstall_key, entry))
        end
        entries
      end

      before do
        allow(Chef::Provider::Package::Windows::RegistryUninstallEntry).to receive(:find_entries).and_return(uninstall_entry)
        allow(::File).to receive(:exist?).with(Chef::Util::PathHelper.canonical_path(resource_source, false)).and_return(false)
      end

      context "uninstall string contains MsiExec.exe" do
        let(:uninstall_hash) do
          [{
            'DisplayVersion' => 'outdated',
            'UninstallString' => "MsiExec.exe /X{guid}"
          }]
        end

        it "sets installer_type to MSI" do
          expect(provider.installer_type).to eql(:msi)
        end
      end

      context "uninstall string ends with uninst.exe" do
        let(:uninstall_hash) do
          [{
            'DisplayVersion' => 'outdated',
            'UninstallString' => %q{"c:/hfhfheru/uninst.exe"}
          }]
        end

        it "sets installer_type to NSIS" do
          expect(provider.installer_type).to eql(:nsis)
        end
      end

      context "uninstall key ends in _is1" do
        let(:uninstall_key) { "blah_is1" }

        it "sets installer_type to inno" do
          expect(provider.installer_type).to eql(:inno)
        end
      end

      context "eninstall entries is empty" do
        before { allow(Chef::Provider::Package::Windows::RegistryUninstallEntry).to receive(:find_entries).and_return([]) }

        it "returns nil" do
          expect(provider.installer_type).to eql(nil)
        end
      end
    end

    it "returns @installer_type if it is set" do
      provider.new_resource.installer_type(:downeaster)
      expect(provider.installer_type).to eql(:downeaster)
    end

    it "sets installer_type to inno if the source contains inno" do
      allow(::Kernel).to receive(:open).and_yield(StringIO.new('blah blah inno blah'))
      expect(provider.installer_type).to eql(:inno)
    end

    it "sets installer_type to wise if the source contains wise" do
      allow(::Kernel).to receive(:open).and_yield(StringIO.new('blah blah wise blah'))
      expect(provider.installer_type).to eql(:wise)
    end

    it "sets installer_type to nsis if the source contains nsis" do
      allow(::Kernel).to receive(:open).and_yield(StringIO.new('blah blah nullsoft blah'))
      expect(provider.installer_type).to eql(:nsis)
    end

    context "source ends in .msi" do
      let(:resource_source) { "microsoft_installer.msi" }

      it "sets installer_type to msi" do
        expect(provider.installer_type).to eql(:msi)
      end
    end

    context "the source is setup.exe" do
      let(:resource_source) { "setup.exe" }

      it "sets installer_type to installshield" do
        allow(::Kernel).to receive(:open).and_yield(StringIO.new(''))
        expect(provider.installer_type).to eql(:installshield)
      end
    end

    context "cannot determine the installer type" do
      let(:resource_source) { "tomfoolery.now" }

      it "raises an error" do
        allow(::Kernel).to receive(:open).and_yield(StringIO.new(''))
        provider.new_resource.installer_type(nil)
        expect { provider.installer_type }.to raise_error(Chef::Exceptions::CannotDetermineWindowsInstallerType)
      end
    end
  end

  describe "action_install" do
    let(:new_resource) { Chef::Resource::WindowsPackage.new("blah.exe") }
    before do
      new_resource.installer_type(:inno)
      allow_any_instance_of(Chef::Provider::Package::Windows::Exe).to receive(:package_version).and_return(new_resource.version)
    end

    context "no version given, discovered or installed" do
      it "installs latest" do
        expect(provider).to receive(:install_package).with("blah.exe", "latest")
        provider.run_action(:install)
      end
    end

    context "no version given or discovered but package is installed" do
      before { allow(provider).to receive(:current_version_array).and_return(["5.5.5"]) }

      it "does not install" do
        expect(provider).not_to receive(:install_package)
        provider.run_action(:install)
      end
    end

    context "a version is given and none is installed" do
      before { new_resource.version('5.5.5') }

      it "installs given version" do
        expect(provider).to receive(:install_package).with("blah.exe", "5.5.5")
        provider.run_action(:install)
      end
    end

    context "a version is given and several are installed" do
      context "given version matches an installed version" do
        before do
          new_resource.version('5.5.5')
          allow(provider).to receive(:current_version_array).and_return([ ["5.5.5", "4.3.0", "1.1.1"] ])
        end
        
        it "does not install" do
          expect(provider).not_to receive(:install_package)
          provider.run_action(:install)
        end
      end

      context "given version does not match an installed version" do
        before do
          new_resource.version('5.5.5')
          allow(provider).to receive(:current_version_array).and_return([ ["5.5.0", "4.3.0", "1.1.1"] ])
        end
        
        it "installs given version" do
          expect(provider).to receive(:install_package).with("blah.exe", "5.5.5")
          provider.run_action(:install)
        end
      end
    end

    context "a version is given and one is installed" do
      context "given version matches installed version" do
        before do
          new_resource.version('5.5.5')
          allow(provider).to receive(:current_version_array).and_return(["5.5.5"])
        end
        
        it "does not install" do
          expect(provider).not_to receive(:install_package)
          provider.run_action(:install)
        end
      end

      context "given version does not match installed version" do
        before do
          new_resource.version('5.5.5')
          allow(provider).to receive(:current_version_array).and_return(["5.5.0"])
        end
        
        it "installs given version" do
          expect(provider).to receive(:install_package).with("blah.exe", "5.5.5")
          provider.run_action(:install)
        end
      end
    end
  end
end