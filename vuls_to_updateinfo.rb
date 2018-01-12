require 'rexml/document'
require 'time'

########################################################################################################################
module IoHelper
  module_function

  def get_vuls_report_path
    report_path = ARGV[0]
    report_path ||= 'localhost.xml'
    return report_path if FileTest.exist?(report_path)
    puts 'vuls report XML file not found.'
    exit
  end

  def get_installed_package_details
    # get installed package arch and epoch
    details = Hash.new
    command_results = `repoquery --all --pkgnarrow=installed --qf="%{name}.%{arch}.%{epoch}"`
    command_results.split(/\n/).each do |line|
      detail = line.split('.')
      pd = PackageDetail.new
      pd.name = detail[0]
      pd.arch = detail[1]
      pd.epoch = detail[2]
      details[pd.name] = pd
    end
    # update epoch by newest package
    command_results = `repoquery --all --pkgnarrow=updates --qf="%{name}.%{epoch}"`
    command_results.split(/\n/).each do |line|
      new_detail = line.split('.')
      details[new_detail[0]].set_new_epoch(new_detail[1])
    end
    details
  end

  def write_xml(doc, filePath)
    File.open(filePath, 'w') do |file|
      doc.write(file, indent=-1, transitive=true)
    end
  end    
end

########################################################################################################################
class PackageDetail
  attr_accessor :name, :arch, :epoch

  def set_new_epoch(value)
    if @epoch < value
      @epoch = value
    end
  end
end

########################################################################################################################
class VulsReportAnalyzer
  def initialize(doc)
    @VulsReport = doc
  end

  def distribution
    @VulsReport.root.get_text('ScanResult/Family').value
  end

  def version
    @VulsReport.root.get_text('ScanResult/Release').value
  end

  def major
    @VulsReport.root.get_text('ScanResult/Release').value.to_i
  end

  def create_update_package_list
    hs = Hash.new
    @VulsReport.elements.each('vulsreport/ScanResult/ScannedCves/Packages') do |package|     
      pi = PackageInfo.new(package)
      next unless pi.installed_package?
      hs[pi.full_name] = pi unless hs.has_key?(pi.full_name)
    end
    hs
  end

  def nvd_infos
    if @nvd_infos.nil?
      @nvd_infos = Array.new
      @VulsReport.elements.each('vulsreport/ScanResult/KnownCves') do |known|
        @nvd_infos << NvdInfo.new(known)
      end
    end
    @nvd_infos
  end

  class NvdInfo
    def initialize(elm_known)
      @elm_known = elm_known
    end
  
    def summary
      @elm_known.get_text('CveDetail/Nvd/Summary').value
    end
  
    def score
      @elm_known.get_text('CveDetail/Nvd/Score').value.to_f
    end
  
    def published_date
      Time.parse(@elm_known.get_text('CveDetail/Nvd/PublishedDate').value).localtime.strftime('%Y-%m-%d %H:%M:%S')
    end
  
    def references
      if @references.nil?
        @references = Array.new
        @elm_known.elements.each('CveDetail/Nvd/References') do |ref|
          @references << ReferrenceInfo.new(ref)
        end
      end
      @references
    end
  
    class ReferrenceInfo
      def initialize(ref)
        @ref = ref
      end
  
      def source
        @ref.get_text('Source').value
      end
  
      def link
        @ref.get_text('Link').value
      end
    end
  
    def packages
      if @packages.nil?
        @packages = Array.new
        @elm_known.elements.each('Packages') do |package|
          pi = PackageInfo.new(package)
          next unless pi.installed_package?
          @packages << pi
        end
      end
      @packages
    end
  end
end

########################################################################################################################
class UpdateInfoBuilder
  def initialize(package_infos, distribution, major)
    @package_infos = package_infos
    @distribution = distribution
    @major = major
    @update_nodes = create_update_nodes
    @scores = create_package_scores(@package_infos.keys)
  end

  def set_nvd_info(nvd)
    nvd.packages.each do |pkg|
      if score_upper?(pkg.full_name, nvd.score)
        get_node(pkg.full_name).get_elements('title')[0].text = get_title(nvd.score, pkg.name)
        get_node(pkg.full_name).get_elements('issued')[0].add_attribute('date', nvd.published_date)
        get_node(pkg.full_name).get_elements('severity')[0].text = get_severity(nvd.score)
        get_node(pkg.full_name).get_elements('description')[0].text = nvd.summary
        update_score(pkg.full_name, nvd.score)
      end
      nvd.references.each do |ref|
        get_node(pkg.full_name).get_elements('references')[0].add_element(create_elm_reference(ref.link, ref.source))
      end
    end
  end

  def to_xml
    root = create_elm_root
    @update_nodes.keys.sort.each do |key|
      root.add_element(@update_nodes[key])
    end
    root
  end

  private
  def create_package_scores(package_keys)
    hs = Hash.new
    package_keys.each do |key|
      hs[key] = 0.to_f
    end
    hs
  end

  def get_os_name
    'centos'.eql?(@distribution) ? 'CentOS ' + @major.to_s : @distribution + @major.to_s
  end

  def create_update_nodes
    hs = Hash.new
    @package_infos.each_value do |pi|
      elm_update = create_elm_update
      elm_update.add_element('id').text = pi.full_name
      elm_update.add_element('title').text = get_title(0, pi.name)
      elm_update.add_element('release').text = get_os_name
      elm_update.add_element('issued', {'date'=>''})
      elm_update.add_element('severity').text = get_severity(0)
      elm_update.add_element('description')
      elm_update.add_element('references')
      collection = elm_update.add_element('pkglist').add_element('collection', {'short'=>'EL-' + @major.to_s})
      collection.add_element('name').text = get_os_name
      collection.add_element(create_elm_package(pi))
      hs[pi.full_name] = elm_update
    end
    hs
  end

  def create_elm_root
    REXML::Element.new('updates')
  end

  def create_elm_update
    upd = REXML::Element.new('update')
    upd.add_attribute('from', 'you@your_domain.com')
    upd.add_attribute('status', 'stable')
    upd.add_attribute('type', 'security')
    upd.add_attribute('version', '1.4')
    upd
  end

  def create_elm_reference(url, type)
    reference = REXML::Element.new('reference')
    reference.add_attributes({'href' => url, 'type' => type})
    reference
  end

  def create_elm_package(pi)
    package = REXML::Element.new('package')
    package.add_attributes({'arch'=>pi.arch, 'epoch'=>pi.epoch, 'name'=>pi.name, 'release'=>pi.release, 'src'=>'', 'version'=>pi.version})
    package.add_element('filename').text = pi.file_name
    package
  end

  def get_node(key)
    @update_nodes[key]
  end

  def score_upper?(key, score)
    @scores[key] < score
  end

  def update_score(key, score)
    @scores[key] = score
  end

  def get_title(score, name)
    get_severity(score) + ' ' + get_os_name + ' ' + name + ' Security Update'
  end

  def get_severity(value)
    if 7.0 <= value
      'Important'
    elsif 4.0 <= value
      'Moderate'
    elsif 0.0 < value
      'Low'
    else
      'Unknown'
    end
  end
end

########################################################################################################################
class PackageInfo
  @@package_details = nil

  def self.package_details=(value)
    @@package_details = value
  end

  def initialize(elm_pkg)
    @elm_pkg = elm_pkg
  end

  def name
    @elm_pkg.get_text('Name').value
  end

  def version
    @elm_pkg.get_text('NewVersion').value
  end

  def release
    @elm_pkg.get_text('NewRelease').value
  end

  def arch
    @@package_details[name].arch
  end

  def epoch
    @@package_details[name].epoch
  end
  
  def full_name
    name + '-' + version + '-' + release + '.' + arch
  end

  def file_name
    full_name + '.rpm'
  end

  def installed_package?
    @@package_details.has_key?(name)
  end
end


########################################################################################################################
# init
PackageInfo.package_details = IoHelper.get_installed_package_details
analyzer = VulsReportAnalyzer.new(REXML::Document.new(open(IoHelper.get_vuls_report_path)))
builder = UpdateInfoBuilder.new(analyzer.create_update_package_list, analyzer.distribution, analyzer.major)

# set nvd information for update nodes
analyzer.nvd_infos.each do |nvd|
  builder.set_nvd_info(nvd)
end

# write updateinfo to file
docUpdateInfo = REXML::Document.new
docUpdateInfo << REXML::XMLDecl.new('1.0', 'UTF-8')
docUpdateInfo.add_element(builder.to_xml)
IoHelper.write_xml(docUpdateInfo, 'updateinfo.xml')
