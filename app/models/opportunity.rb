# == Schema Information
# Schema version: 14
#
# Table name: opportunities
#
#  id          :integer(4)      not null, primary key
#  uuid        :string(36)
#  user_id     :integer(4)
#  campaign_id :integer(4)
#  assigned_to :integer(4)
#  name        :string(64)      default(""), not null
#  access      :string(8)       default("Private")
#  source      :string(32)
#  stage       :string(32)
#  probability :integer(4)
#  amount      :decimal(12, 2)
#  discount    :decimal(12, 2)
#  closes_on   :date
#  notes       :text
#  deleted_at  :datetime
#  created_at  :datetime
#  updated_at  :datetime
#

class Opportunity < ActiveRecord::Base
  belongs_to :user
  belongs_to :account
  belongs_to :campaign
  has_one :account_opportunity, :dependent => :destroy
  has_one :account, :through => :account_opportunity
  has_many :contact_opportunities, :dependent => :destroy
  has_many :contacts, :through => :contact_opportunities, :uniq => true
  has_many :permissions, :as => :asset, :include => :user
  named_scope :my, lambda { |user| { :joins => :permissions, :conditions => ["opportunities.user_id=? OR opportunities.assigned_to=? OR permissions.user_id=?", user, user, user], :order => "id DESC" } }
  uses_mysql_uuid
  acts_as_paranoid

  validates_presence_of :name, :message => "^Please specify the opportunity name."
  validates_uniqueness_of :name, :scope => :user_id
  validates_numericality_of [ :probability, :amount, :discount ], :allow_nil => true
  validate :users_for_shared_access

  #----------------------------------------------------------------------------
  def weighted_amount
    (amount || 0) * (probability || 0) / 100.0
  end

  # Backend handler for [Create New Opportunity] form (see opportunity/create).
  #----------------------------------------------------------------------------
  def save_with_account_and_permissions(params)
    account = Account.create_or_select_for(self, params[:account], params[:users])
    self.account_opportunity = AccountOpportunity.new(:account => account, :opportunity => self) unless account.id.blank?
    save_with_permissions(params[:users])
  end

  # Save the opportunity along with its permissions if any.
  #----------------------------------------------------------------------------
  def save_with_permissions(users)
    if users && self[:access] == "Shared"
      users.each { |id| self.permissions << Permission.new(:user_id => id, :asset => self) }
    end
    save
  end

  # Save the opportunity copying model permissions (Lead).
  #----------------------------------------------------------------------------
  def save_with_model_permissions(model)
    self.access = model.access
    if model.access == "Shared"
      model.permissions.each do |permission|
        self.permissions << Permission.new(:user_id => permission.user_id, :asset => self)
      end
    end
    save
  end

  # Class methods.
  #----------------------------------------------------------------------------
  def self.create_for(model, account, params, users)
    opportunity = Opportunity.new(params)

    # Save the opportunity if its name was specified and account has no errors.
    if opportunity.name? && account.errors.empty?
      # Note: opportunity.account = account doesn't seem to work here.
      opportunity.account_opportunity = AccountOpportunity.new(:account => account, :opportunity => opportunity) unless account.id.blank?
      if opportunity.access != "Lead" || model.nil?
        opportunity.save_with_permissions(users)
      else
        opportunity.save_with_model_permissions(model)
      end
    end
    opportunity
  end

  private
  # Make sure at least one user has been selected if the contact is being shared.
  #----------------------------------------------------------------------------
  def users_for_shared_access
    errors.add(:access, "^Please specify users to share the opportunity with.") if self[:access] == "Shared" && !self.permissions.any?
  end

end