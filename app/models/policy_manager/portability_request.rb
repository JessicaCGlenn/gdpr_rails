require "aasm"

module PolicyManager
  class PortabilityRequest < ApplicationRecord
    # include Paperclip::Glue

    belongs_to :user, class_name: Config.user_resource.to_s, foreign_key: 'user_id'

    has_one_attached :attachment

    # has_attached_file :attachment, 
    #   path: Config.exporter.try(:attachment_path) || Rails.root.join("tmp/portability/:id/build.zip").to_s, 
    #   storage: Config.exporter.try(:attachment_storage) || :filesystem,
    #   s3_permissions: :private

    # do_not_validate_attachment_file_type :attachment

    include AASM

    aasm column: :state do
      state :pending, :initial => true, :after_enter => :notify_progress_to_admin
      state :progress, :after_enter => :handle_progress
      state :completed, :after_enter => :notify_completeness

      event :confirm do
        transitions from: :pending, to: :progress
      end

      event :complete do
        transitions from: :progress, to: :completed
      end
    end

    def user_email
      self.user.email
    end

    def file_remote_url=(url_value)
      self.attachment.attach(io: open(url_value), filename: "portability_request_#{self.id}.zip") unless url_value.blank?
      # self.attachment = File.open(url_value) unless url_value.blank?
      # self.save
      self.complete!
    end

    def download_link
      url = Rails.application.routes.url_helpers.rails_blob_url(self.attachment, disposition: "attachment", host: Config.exporter.host)
    end

    def handle_progress
      notify_progress
      perform_job
    end

    def perform_job
      ExporterJob.set(queue: :default).perform_later(self.user.id)
    end

    def notify_progress
      if Config.exporter.progress_callback.present?
        Config.exporter.progress_callback.call(self.id)
      else
        PortabilityMailer.progress_notification(self.id).deliver_now
      end
    end

    def notify_progress_to_admin
      if Config.exporter.admin_progress_callback.present?
        Config.exporter.admin_progress_callback.call(self.id)
      else
        PortabilityMailer.admin_notification(self.id).deliver_now
      end
    end

    def notify_completeness
      if Config.exporter.completed_callback.present?
        Config.exporter.completed_callback.call(self.id)
      else
        PortabilityMailer.completed_notification(self.id).deliver_now
      end
    end

  end
end
