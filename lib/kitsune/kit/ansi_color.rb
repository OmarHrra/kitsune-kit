module AnsiColor
  COLORS = {
    black:   30,
    red:     31,
    green:   32,
    yellow:  33,
    blue:    34,
    magenta: 35,
    cyan:    36,
    white:   37,

    light_black:   90,
    light_red:     91,
    light_green:   92,
    light_yellow:  93,
    light_blue:    94,
    light_magenta: 95,
    light_cyan:    96,
    light_white:   97
  }

  BACKGROUNDS = {
    black:   40,
    red:     41,
    green:   42,
    yellow:  43,
    blue:    44,
    magenta: 45,
    cyan:    46,
    white:   47,

    light_black:   100,
    light_red:     101,
    light_green:   102,
    light_yellow:  103,
    light_blue:    104,
    light_magenta: 105,
    light_cyan:    106,
    light_white:   107
  }

  STYLES = {
    bold:      1,
    italic:    3,
    underline: 4
  }

  def self.colorize(text, color: nil, background: nil, style: nil)
    codes = []
    codes << COLORS[color] if color
    codes << BACKGROUNDS[background] if background
    codes << STYLES[style] if style

    raise ArgumentError, "No valid formatting options given" if codes.empty?

    "\e[#{codes.join(';')}m#{text}\e[0m"
  end

  def self.demo
    puts "Text Colors:"
    COLORS.each_key do |color|
      puts colorize("  #{color.to_s.ljust(15)}", color: color)
    end
  
    puts "\nBackground Colors:"
    BACKGROUNDS.each_key do |bg|
      puts colorize("  #{bg.to_s.ljust(15)}", background: bg)
    end
  
    puts "\nStyles:"
    STYLES.each_key do |style|
      puts colorize("  #{style.to_s.ljust(15)}", color: :white, style: style)
    end
  
    puts "\nCombined Example:"
    puts colorize("  bold green on light_black  ", color: :green, background: :light_black, style: :bold)
  end
end
