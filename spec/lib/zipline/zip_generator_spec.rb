require 'spec_helper'
require 'tempfile'

describe Zipline::ZipGenerator do
  before { Fog.mock! }
  let(:file_attributes){ {
    key: 'fog_file_tests',
    body: 'some body',
    public: true
  }}
  let(:directory_attributes){{
    key: 'fog_directory'
  }}
  let(:storage_attributes){{
    aws_access_key_id: 'fake_access_key_id',
    aws_secret_access_key: 'fake_secret_access_key',
    provider: 'AWS'
  }}
  let(:storage){ Fog::Storage.new(storage_attributes)}
  let(:directory){ storage.directories.create(directory_attributes) }
  let(:file){ directory.files.create(file_attributes) }

  describe '.normalize' do
    let(:generator){ Zipline::ZipGenerator.new([])}
    context 'CarrierWave' do
      context 'Remote' do
        let(:file){ CarrierWave::Storage::Fog::File.new(nil,nil,nil) }
        it 'extracts the url' do
          allow(file).to receive(:url).and_return('fakeurl')
          expect(File).not_to receive(:open)
          expect(generator.normalize(file)).to eq({url: 'fakeurl'})
        end
      end
      context 'Local' do
        let(:file){ CarrierWave::SanitizedFile.new(Tempfile.new('t')) }
        it 'creates a File' do
          allow(file).to receive(:path).and_return('spec/fakefile.txt')
          normalized = generator.normalize(file)
          expect(normalized.keys).to include(:file)
          expect(normalized[:file]).to be_a File
        end
      end
      context 'CarrierWave::Uploader::Base' do
        let(:uploader) { Class.new(CarrierWave::Uploader::Base).new }

        context 'Remote' do
          let(:file){ CarrierWave::Storage::Fog::File.new(nil,nil,nil) }
          it 'extracts the url' do
            allow(uploader).to receive(:file).and_return(file)
            allow(file).to receive(:url).and_return('fakeurl')
            expect(File).not_to receive(:open)
            expect(generator.normalize(uploader)).to eq({url: 'fakeurl'})
          end
        end

        context 'Local' do
          let(:file){ CarrierWave::SanitizedFile.new(Tempfile.new('t')) }
          it 'creates a File' do
            allow(uploader).to receive(:file).and_return(file)
            allow(file).to receive(:path).and_return('spec/fakefile.txt')
            normalized = generator.normalize(uploader)
            expect(normalized.keys).to include(:file)
            expect(normalized[:file]).to be_a File
          end
        end
      end
    end
    context 'Paperclip' do
      context 'Local' do
        let(:file){ Paperclip::Attachment.new(:name, :instance) }
        it 'creates a File' do
          allow(file).to receive(:path).and_return('spec/fakefile.txt')
          normalized = generator.normalize(file)
          expect(normalized.keys).to include(:file)
          expect(normalized[:file]).to be_a File
        end
      end
      context 'Remote' do
        let(:file){ Paperclip::Attachment.new(:name, :instance, storage: :s3) }
        it 'creates a URL' do
          allow(file).to receive(:expiring_url).and_return('fakeurl')
          expect(File).to_not receive(:open)
          expect(generator.normalize(file)).to include(url: 'fakeurl')
        end
      end
    end
    context 'ActiveStorage' do
      module ActiveStorage
        class Attached
          class One < Attached
          end
        end
        class Attachment; end
        class Blob; end
      end

      context 'Attached::One' do
        it 'extracts url' do
          attached = create_attached_one
          allow_any_instance_of(Object).to receive(:defined?).and_return(true)

          normalized = generator.normalize(attached)

          expect(normalized.keys).to include(:url)
          expect(normalized[:url]).to eq('fakeurl')
        end
      end

      context 'Attachment' do
        it 'extracts url' do
          attachment = create_attachment
          allow_any_instance_of(Object).to receive(:defined?).and_return(true)

          normalized = generator.normalize(attachment)

          expect(normalized.keys).to include(:url)
          expect(normalized[:url]).to eq('fakeurl')
        end
      end

      context 'Blob' do
        it 'extracts url' do
          blob = create_blob
          allow_any_instance_of(Object).to receive(:defined?).and_return(true)

          normalized = generator.normalize(blob)

          expect(normalized.keys).to include(:url)
          expect(normalized[:url]).to eq('fakeurl')
        end
      end

      def create_attached_one
        attached = ActiveStorage::Attached::One.new
        blob = create_blob
        allow(attached).to receive(:blob).and_return(blob)
        attached
      end

      def create_attachment
        attachment = ActiveStorage::Attachment.new
        blob = create_blob
        allow(attachment).to receive(:blob).and_return(blob)
        attachment
      end

      def create_blob
        blob = ActiveStorage::Blob.new
        allow(blob).to receive(:service_url).and_return('fakeurl')
        blob
      end
    end
    context 'Fog' do
      it 'extracts url' do
        allow(file).to receive(:url).and_return('fakeurl')
        expect(File).not_to receive(:open)
        expect(generator.normalize(file)).to eq(url:  'fakeurl')
      end
    end
    context 'IOStream' do
      let(:file){ StringIO.new('passthrough')}
      it 'passes through' do
        expect(generator.normalize(file)).to eq(file: file)
      end
    end
    context 'invalid' do
      let(:file){ Thread.new{} }
      it 'raises error' do
        expect{generator.normalize(file)}.to raise_error(ArgumentError)
      end
    end
  end

  describe 'passing an options hash' do
    let(:file) { StringIO.new('passthrough') }

    context 'with optional arguments' do
      let(:mtime) { 1.day.ago }
      let(:generator) do
        Zipline::ZipGenerator.new([[file, 'test', modification_time: mtime]])
      end

      it 'passes the options hash through handle_file' do
        expect(generator).to receive(:handle_file)
          .with(anything, anything, anything, modification_time: mtime)
        generator.each { |_| 'Test' }
      end

      it 'passes the options hash to ZipTricks' do
        allow(file).to receive(:url).and_return('fakeurl')
        expect_any_instance_of(ZipTricks::Streamer).to receive(:write_deflated_file)
          .with(anything, modification_time: mtime)
        generator.each { |_| 'Test' }
      end
    end

    context 'without optional arguments' do
      let(:generator) do
        Zipline::ZipGenerator.new([[file, 'test']])
      end

      it 'passes the options hash through handle_file' do
        expect(generator).to receive(:handle_file)
          .with(anything, anything, anything, {})
        generator.each { |_| 'Test' }
      end

      it 'passes the options hash to ZipTricks' do
        allow(file).to receive(:url).and_return('fakeurl')
        expect_any_instance_of(ZipTricks::Streamer).to receive(:write_deflated_file)
          .with(anything, {})
        generator.each { |_| 'Test' }
      end
    end
  end
end
