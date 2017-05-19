class ExportedPlan < ActiveRecord::Base
  include GlobalHelpers
  include SettingsTemplateHelper

# TODO: REMOVE AND HANDLE ATTRIBUTE SECURITY IN THE CONTROLLER!
  attr_accessible :plan_id, :user_id, :format, :user, :plan, :as => [:default, :admin]

  #associations between tables
  belongs_to :plan
  belongs_to :user

  VALID_FORMATS = ['csv', 'html', 'pdf', 'text', 'docx']

  validates :format, inclusion: { 
    in: VALID_FORMATS,
    message: -> (object, data) do 
      _('%{value} is not a valid format') % { :value => data[:value] } 
    end 
  }
  validates :plan, :format, presence: {message: _("can't be blank")}

  # Store settings with the exported plan so it can be recreated later
  # if necessary (otherwise the settings associated with the plan at a
  # given time can be lost)
  has_settings :export, class_name: 'Settings::Template' do |s|
    s.key :export, defaults: Settings::Template::DEFAULT_SETTINGS
  end

# TODO: Consider removing the accessor methods, they add no value. The view/controller could
#       just access the value directly from the project/plan: exported_plan.plan.project.title

  # Getters to match Settings::Template::VALID_ADMIN_FIELDS
  def project_name
    name = self.plan.template.title
    name += " - #{self.plan.title}" if self.plan.template.phases.count > 1
    name
  end

  def project_identifier
    self.plan.identifier
  end

  def grant_title
    self.plan.grant_number
  end

  def principal_investigator
    self.plan.principal_investigator
  end

  def project_data_contact
    self.plan.data_contact
  end

  def project_description
    self.plan.description
  end

  def owner
    self.plan.roles.to_a.select{ |role| role.creator? }.first.user
  end

  def funder
    org = self.plan.template.try(:org)
    org.name if org.present? && org.funder?
  end

  def institution
    plan.owner.org.try(:name)
  end

  def orcid
    scheme = IdentifierScheme.find_by(name: 'orcid')
    if self.owner.nil?
      ''
    else
      orcid = self.owner.user_identifiers.where(identifier_scheme: scheme).first
      (orcid.nil? ? '' : orcid.identifier)
    end
  end

  def sections
    phase_id = self.phase_id ||= self.plan.template.phases.first.id # Use the first phase if none was specified
    sections = Phase.find(phase_id).sections
    sections.sort_by(&:number)
  end

  def questions_for_section(section_id)
    questions.where(section_id: section_id).sort_by(&:number)
  end

  def admin_details
    @admin_details ||= self.settings(:export).fields[:admin]
  end

  # Retrieves the title field
  def title
    self.settings(:export).title
  end

  # Export formats

  def as_csv
    CSV.generate do |csv|
      csv << [_('Section'),_('Question'),_('Answer'),_('Selected option(s)'),_('Answered by'),_('Answered at')]
      self.sections.each do |section|
        self.questions_for_section(section).each do |question|
          answer = self.plan.answer(question.id)
          q_format = question.question_format
          if q_format.title == _('Check box') || q_format.title == _('Multi select box') ||
            q_format.title == _('Radio buttons') || q_format.title == _('Dropdown')
            options_string = answer.options.collect {|o| o.text}.join('; ')
          else
            options_string = ''
          end
          csv << [section.title, sanitize_text(question.text), sanitize_text(answer.text), options_string, user.name, answer.updated_at]
        end
      end
    end
  end

  def as_txt
    output = "#{self.plan.title}\n\n#{self.plan.template.title}\n"
    output += "\n"+_('Details')+"\n\n"
    puts 'admin_details: '+self.admin_details.inspect

    self.admin_details.each do |at|
        value = self.send(at)
        if value.present?
          output += admin_field_t(at.to_s) + ": " + value + "\n"
        else
          output += admin_field_t(at.to_s) + ": " + _('-') + "\n"
        end
    end

    self.sections.each do |section|
      output += "\n#{section.title}\n"

      self.questions_for_section(section).each do |question|
        qtext = sanitize_text( question.text.gsub(/<li>/, '  * ') )
        output += "\n* #{qtext}"
        answer = self.plan.answer(question.id, false)

        if answer.nil?
          output += _('Question not answered.')+ "\n"
        else
          q_format = question.question_format
          if q_format.title == _('Check box') || q_format.title == _('Multi select box') ||
            q_format.title == _('Radio buttons') || q_format.title == _('Dropdown')
            output += answer.options.collect {|o| o.text}.join("\n")
            if question.option_comment_display
              output += "\n#{sanitize_text(answer.text)}\n"
            end
          else
            output += "\n#{sanitize_text(answer.text)}\n"
          end
        end
      end
    end

    output
  end

private

  def questions
    @questions ||= begin
      question_settings = self.settings(:export).fields[:questions]

      return [] if question_settings.is_a?(Array) && question_settings.empty?

      questions = if question_settings.present? && question_settings != :all
        Question.where(id: question_settings)
      else
        Question.where(section_id: self.plan.sections.collect {|s| s.id })
      end

      questions.order(:number)
    end
  end

  def sanitize_text(text)
    if (!text.nil?) then ActionView::Base.full_sanitizer.sanitize(text.gsub(/&nbsp;/i,"")) end
  end

end
