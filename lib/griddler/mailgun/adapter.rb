module Griddler
  module Mailgun
    class Adapter
      attr_reader :params

      def initialize(params)
        @params = params
      end

      def self.normalize_params(params)
        adapter = new(params)
        adapter.normalize_params
      end

      def normalize_params
        h = {
          to: to_recipients,
          cc: cc_recipients,
          bcc: Array.wrap(param_or_header(:Bcc)),
          from: determine_sender,
          subject: params[:subject],
          text: params['body-plain'],
          html: params['body-html'],
          attachments: attachment_files,
          headers: serialized_headers
        }
        if !params[:recipient].blank?
          h[:recipient] = Griddler::EmailParser.parse_address(params[:recipient])
        end
        if !params['content-id-map'].blank?
          map = {}
          list = JSON.parse(params['content-id-map'])
          list.each do |k, v|
            if v.to_s.include?('-')
              index = v.split('-')[1].to_i - 1
              key = k.to_s.sub('<', '').sub('>', '')
              map[index] = key
            end
          end
          h[:content_id_map] = map
        end
        return h        
      end

      def recipient
        params[:recipient]
      end

      def content_id_map
        params[:content_id_map]
      end

    private

      def determine_sender
        sender = param_or_header(:From)
        sender ||= params[:sender]
      end

      def to_recipients
        to_emails = param_or_header(:To)
        to_emails ||= params[:recipient]
        to_emails.to_s.split(',').map(&:strip)
      end

      def cc_recipients
        cc = param_or_header(:Cc) || ''
        cc.to_s.split(',').map(&:strip)
      end

      def headers
        @headers ||= extract_headers
      end

      def extract_headers
        extracted_headers = {}
        if params['message-headers']
          parsed_headers = JSON.parse(params['message-headers'])
          parsed_headers.each{ |h| extracted_headers[h[0]] = h[1] }
        end
        ActiveSupport::HashWithIndifferentAccess.new(extracted_headers)
      end

      def serialized_headers

        # Griddler expects unparsed headers to pass to ActionMailer, which will manually
        # unfold, split on line-endings, and parse into individual fields.
        #
        # Mailgun already provides fully-parsed headers in JSON -- so we're reconstructing
        # fake headers here for now, until we can find a better way to pass the parsed
        # headers directly to Griddler

        headers.to_a.collect { |header| "#{header[0]}: #{header[1]}" }.join("\n")
      end

      def param_or_header(key)
        if params[key].present?
          params[key]
        elsif headers[key].present?
          headers[key]
        else
          nil
        end
      end

      def attachment_files
        attachment_count = params['attachment-count'].to_i

        attachment_count.times.map do |index|
          params.delete("attachment-#{index+1}")
        end
      end
    end
  end
end
