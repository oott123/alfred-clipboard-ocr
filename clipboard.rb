

module Clipboard
  def paste(_ = nil)
    `pbpaste`
  end

  def copy(data)
    
    paste
  end

  def clear
    copy ''
  end
end
